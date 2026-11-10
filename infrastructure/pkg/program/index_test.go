package program_test

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	siteModel "github.com/muhlba91/homelab-router-infrastructure/pkg/model/config/site"
	"github.com/muhlba91/homelab-router-infrastructure/pkg/program"
	"github.com/muhlba91/homelab-router-infrastructure/pkg/util"
	"github.com/muhlba91/homelab-router-infrastructure/test/mocks"
)

// project is the Pulumi project (its name scopes the stack configuration).
const project = "homelab-router-infrastructure"

// enabledLine matches a site file's switch.
var enabledLine = regexp.MustCompile(`(?m)^enabled: false$`)

// renderOptions configure a render.
type renderOptions struct {
	// enable enables every site file.
	enable bool
	// enrollKey sets the CrowdSec console enroll key in the stack configuration.
	enrollKey bool
	// sites are additional site files: file name (without .yml) -> content.
	sites map[string]string
}

// requiredFields are the fields every site file needs besides its name.
const requiredFields = `hardware: {profile: qemu, disk: /dev/sda}
network:
  domain: a.example
  wan:
    mac: "00:00:00:00:00:01"
    interface: wan0
    v4: {method: dhcp}
  lan:
    mac: "00:00:00:00:00:02"
    interface: lan0
    v4: {address: 10.0.0.1, netmask: 24, network: 10.0.0.0}
    v6: {address: "fd00::1", netmask: 64, network: "fd00::", supernet: "fd00::/48"}
  trustedNetworks: {}
dhcp:
  v4: {start: 10.0.0.10, end: 10.0.0.20}
  v6: {start: "fd00::10", end: "fd00::20"}
`

// render runs the program under mocks in dir, with the site files of assets/sites, the site template and the
// additional sites of the options, and checks the written files.
func render(t *testing.T, dir string, opts renderOptions) {
	t.Helper()

	assets, err := filepath.Abs("../../assets")
	require.NoError(t, err)
	require.NoError(t, os.RemoveAll(filepath.Join(dir, "assets")))
	require.NoError(t, os.CopyFS(filepath.Join(dir, "assets"), os.DirFS(assets)))

	// The site template sets every field: rendered as a site too, so the whole template is checked.
	siteTemplate, err := os.ReadFile(filepath.Join(dir, "assets", "templates", "site.yml"))
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(filepath.Join(dir, "assets", "sites", "site.yml"), siteTemplate, 0o600))
	for name, content := range opts.sites {
		require.NoError(t, os.WriteFile(filepath.Join(dir, "assets", "sites", name+".yml"), []byte(content), 0o600))
	}

	files, err := filepath.Glob(filepath.Join(dir, "assets", "sites", "*.yml"))
	require.NoError(t, err)
	require.NotEmpty(t, files)
	if opts.enable {
		for _, file := range files {
			content, rErr := os.ReadFile(file)
			require.NoError(t, rErr)
			require.NoError(t, os.WriteFile(file, enabledLine.ReplaceAll(content, []byte("enabled: true")), 0o600))
		}
	}

	t.Chdir(dir)
	stackConfig := `{"` + project + `:bucketId":"mock-bucket"`
	if opts.enrollKey {
		stackConfig += `,"` + project + `:crowdsec":"{\"enrollKey\":\"mock-key\"}"`
	}
	t.Setenv("PULUMI_CONFIG", stackConfig+"}")
	require.NoError(t, pulumi.RunErr(program.Run, pulumi.WithMocks(project, "test", mocks.Mocks{})))

	sites, err := util.ParseSitesFromFiles("./assets/sites")
	require.NoError(t, err)

	for _, site := range sites {
		if opts.enable {
			assert.True(t, site.IsEnabled(), site.Name)
		}
		assert.FileExists(t, filepath.Join("outputs", "sites", site.Name, "vars.nix"))
		if site.IsEnabled() {
			assertKeys(t, site, opts.enrollKey)
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

// assertKeys checks the key and secret files of an enabled site: the ones every site gets, and the optional ones
// exactly when the site uses their feature (the CrowdSec console only with an enroll key, else off in vars.nix too).
func assertKeys(t *testing.T, site *siteModel.Config, enrollKey bool) {
	t.Helper()

	keys := filepath.Join("outputs", "keys", site.Name)
	secrets := filepath.Join(keys, "secrets")
	assert.FileExists(t, filepath.Join(keys, "deploy-key"))
	assert.FileExists(t, filepath.Join(keys, "adguard-password"))
	assert.FileExists(t, filepath.Join(secrets, "ssh-host-key"))
	assert.FileExists(t, filepath.Join(secrets, "adguard-password-hash"))

	optional := map[string]bool{
		"netbird-setup-key":   site.UsesNetbird(),
		"nut-password":        site.UsesUPS(),
		"crowdsec-enroll-key": site.UsesCrowdSecConsole() && enrollKey,
	}
	if site.UsesCrowdSecConsole() {
		vars, err := os.ReadFile(filepath.Join("outputs", "sites", site.Name, "vars.nix"))
		require.NoError(t, err)
		assert.Equal(
			t,
			enrollKey,
			strings.Contains(string(vars), "security.crowdsec.console.enable = true;"),
			site.Name,
		)
	}
	for name, used := range optional {
		if used {
			assert.FileExists(t, filepath.Join(secrets, name))
		} else {
			assert.NoFileExists(t, filepath.Join(secrets, name))
		}
	}
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

	render(t, dir, renderOptions{enrollKey: true})

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

	render(t, dir, renderOptions{enable: true, enrollKey: true})
}

// TestRunWithoutEnrollKey renders every site file enabled without the CrowdSec enroll key: the console enrollment is
// dropped (vars.nix and secrets).
func TestRunWithoutEnrollKey(t *testing.T) {
	render(t, t.TempDir(), renderOptions{enable: true})
}

// TestRunVars checks the rendered vars.nix: no hostname (the Nix option defaults to the name), no NetBird token, and
// no IPv6 on the WAN of a site without one.
func TestRunVars(t *testing.T) {
	dir := t.TempDir()
	render(t, dir, renderOptions{
		enable: true,
		sites:  map[string]string{"plain": "name: plain\nenabled: true\n" + requiredFields},
	})

	vars, err := os.ReadFile(filepath.Join("outputs", "sites", "plain", "vars.nix"))
	require.NoError(t, err)
	assert.Contains(t, string(vars), "v6 = {\n        method = \"none\";\n      };")
	assert.Contains(t, string(vars), "v4 = {\n        method = \"dhcp\";\n      };")
	assert.Contains(t, string(vars), "mgmt = {\n      address = \"10.0.0.1\";", "defaults to the LAN address")
	assert.Contains(t, string(vars), "nat66.enable = true;")
	assert.NotContains(t, string(vars), "bgp")

	sites, err := filepath.Glob(filepath.Join("outputs", "sites", "*", "vars.nix"))
	require.NoError(t, err)
	require.Len(t, sites, 6)
	for _, file := range sites {
		content, rErr := os.ReadFile(file)
		require.NoError(t, rErr)
		assert.NotContains(t, string(content), "hostname = \""+filepath.Base(filepath.Dir(file)), file)
		assert.NotContains(t, string(content), "mock-pat", file)
	}
}
