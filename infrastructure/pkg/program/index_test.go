package program_test

import (
	"os"
	"path/filepath"
	"regexp"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/program"
	"github.com/muhlba91/homelab-router-infrastructure/pkg/util"
	"github.com/muhlba91/homelab-router-infrastructure/test/mocks"
)

// project is the Pulumi project (its name scopes the stack configuration).
const project = "homelab-router-infrastructure"

// enabledLine matches a site file's switch.
var enabledLine = regexp.MustCompile(`(?m)^enabled: false$`)

// render runs the program under mocks in dir, with the site files of assets/sites and the site template (all of them
// enabled if enable is set) and checks the written files.
func render(t *testing.T, dir string, enable bool) {
	t.Helper()

	assets, err := filepath.Abs("../../assets")
	require.NoError(t, err)
	require.NoError(t, os.RemoveAll(filepath.Join(dir, "assets")))
	require.NoError(t, os.CopyFS(filepath.Join(dir, "assets"), os.DirFS(assets)))

	// The site template sets every field: rendered as a site too, so the whole template is checked.
	template, err := os.ReadFile(filepath.Join(dir, "assets", "templates", "site.yml"))
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(filepath.Join(dir, "assets", "sites", "site.yml"), template, 0o600))

	files, err := filepath.Glob(filepath.Join(dir, "assets", "sites", "*.yml"))
	require.NoError(t, err)
	require.NotEmpty(t, files)
	if enable {
		for _, file := range files {
			content, rErr := os.ReadFile(file)
			require.NoError(t, rErr)
			require.NoError(t, os.WriteFile(file, enabledLine.ReplaceAll(content, []byte("enabled: true")), 0o600))
		}
	}

	t.Chdir(dir)
	t.Setenv("PULUMI_CONFIG", `{"`+project+`:bucketId":"mock-bucket"}`)
	require.NoError(t, pulumi.RunErr(program.Run, pulumi.WithMocks(project, "test", mocks.Mocks{})))

	sites, err := util.ParseSitesFromFiles("./assets/sites")
	require.NoError(t, err)

	for _, site := range sites {
		if enable {
			assert.True(t, site.IsEnabled(), site.Name)
		}
		assert.FileExists(t, filepath.Join("outputs", "sites", site.Name, "vars.nix"))
		if site.IsEnabled() {
			assert.FileExists(t, filepath.Join("outputs", "keys", site.Name, "deploy-key"))
			assert.FileExists(t, filepath.Join("outputs", "keys", site.Name, "secrets", "ssh-host-key"))
			assert.FileExists(t, filepath.Join("outputs", "keys", site.Name, "adguard-password"))
			assert.FileExists(t, filepath.Join("outputs", "keys", site.Name, "secrets", "adguard-password-hash"))
			if site.UsesNetbird() {
				assert.FileExists(t, filepath.Join("outputs", "keys", site.Name, "secrets", "netbird-setup-key"))
			}
			if site.UsesUPS() {
				assert.FileExists(t, filepath.Join("outputs", "keys", site.Name, "secrets", "nut-password"))
			}
		} else {
			assert.NoDirExists(t, filepath.Join("outputs", "keys", site.Name))
		}
	}

	// The vars folder is the router fleet's Nix input: nothing but <site>/vars.nix.
	require.NoError(
		t,
		filepath.WalkDir(filepath.Join("outputs", "sites"), func(path string, entry os.DirEntry, wErr error) error {
			if wErr == nil && !entry.IsDir() {
				assert.Equal(t, "vars.nix", entry.Name(), path)
			}
			return wErr
		}),
	)
}

// TestRunAsIs renders the site files as they are (only enabled sites get keys); files of an earlier run whose site is
// gone are removed.
func TestRunAsIs(t *testing.T) {
	dir := t.TempDir()
	stale := []string{filepath.Join("outputs", "sites", "gone"), filepath.Join("outputs", "keys", "gone")}
	for _, path := range stale {
		require.NoError(t, os.MkdirAll(filepath.Join(dir, path), 0o700))
		require.NoError(t, os.WriteFile(filepath.Join(dir, path, "file"), []byte("stale"), 0o600))
	}

	render(t, dir, false)

	for _, path := range stale {
		assert.NoDirExists(t, path)
	}
}

// TestRunEnabled renders every site file enabled (keys and secrets). RENDER_DIR keeps the result for the router
// fleet's checks: `OUTPUTS=$RENDER_DIR/outputs ./router check` in nix/.
func TestRunEnabled(t *testing.T) {
	dir := os.Getenv("RENDER_DIR")
	if dir == "" {
		dir = t.TempDir()
	}
	require.NoError(t, os.MkdirAll(dir, 0o700))

	render(t, dir, true)
}
