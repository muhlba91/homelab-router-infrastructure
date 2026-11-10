package util_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/util"
)

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

// writeSites writes one site file per entry (file name -> site name) into a new directory.
func writeSites(t *testing.T, files map[string]string) string {
	t.Helper()

	dir := t.TempDir()
	for file, name := range files {
		require.NoError(t, os.WriteFile(filepath.Join(dir, file), []byte("name: "+name+"\n"+requiredFields), 0o600))
	}
	return dir
}

// TestParseSitesDeployOrder reads the deploy order from the file name prefix; a file without one has none.
func TestParseSitesDeployOrder(t *testing.T) {
	sites, err := util.ParseSitesFromFiles(writeSites(t, map[string]string{
		"010-site-a.yml": "site-a",
		"site-b.yaml":    "site-b",
	}))
	require.NoError(t, err)
	require.Len(t, sites, 2)

	assert.Equal(t, "site-a", sites[0].Name)
	require.NotNil(t, sites[0].DeployOrder)
	assert.Equal(t, 10, *sites[0].DeployOrder)
	assert.Equal(t, "site-b", sites[1].Name)
	assert.Nil(t, sites[1].DeployOrder)
}

// TestParseSitesNameMismatch rejects a file whose name (without the prefix) is not its site's name.
func TestParseSitesNameMismatch(t *testing.T) {
	_, err := util.ParseSitesFromFiles(writeSites(t, map[string]string{"010-site-a.yml": "site-b"}))
	require.Error(t, err)
}

// TestParseSitesDuplicate rejects a site defined in two files.
func TestParseSitesDuplicate(t *testing.T) {
	_, err := util.ParseSitesFromFiles(writeSites(t, map[string]string{
		"010-site-a.yml": "site-a",
		"020-site-a.yml": "site-a",
	}))
	require.Error(t, err)
}

// TestParseSitesNoName rejects a file named only by its extension.
func TestParseSitesNoName(t *testing.T) {
	for _, file := range []string{".yml", ".yaml"} {
		_, err := util.ParseSitesFromFiles(writeSites(t, map[string]string{file: "site-a"}))
		require.Error(t, err, file)
	}
}

// writeSite writes one site file with the given content into a new directory.
func writeSite(t *testing.T, file, content string) string {
	t.Helper()

	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, file), []byte(content), 0o600))
	return dir
}

// TestParseSitesInvalidName rejects site names that are not hostname labels.
func TestParseSitesInvalidName(t *testing.T) {
	for _, name := range []string{"..", "Site-A", "site_a", "-site"} {
		_, err := util.ParseSitesFromFiles(writeSite(t, name+".yml", "name: "+name+"\n"+requiredFields))
		require.Error(t, err, name)
	}
}

// TestParseSitesMultipleDocuments rejects a file with a second YAML document.
func TestParseSitesMultipleDocuments(t *testing.T) {
	_, err := util.ParseSitesFromFiles(
		writeSite(t, "site-a.yml", "name: site-a\n"+requiredFields+"---\nenabled: true\n"),
	)
	require.Error(t, err)
}

// TestParseSitesEmptyLists rejects empty lists that would render like omitted ones (open instead of closed).
func TestParseSitesEmptyLists(t *testing.T) {
	for name, firewall := range map[string]string{
		"forward from":  "forwards:\n    v4:\n      - proto: tcp\n        ports: [80]\n        to: 10.0.0.2\n        from: []\n",
		"service from":  "services:\n    ssh:\n      from: []\n",
		"service ports": "services:\n    ssh:\n      ports: []\n",
		"nil service":   "services:\n    ssh:\n",
		"nil forward":   "forwards:\n    v4:\n      -\n",
	} {
		_, err := util.ParseSitesFromFiles(
			writeSite(t, "site-a.yml", "name: site-a\n"+requiredFields+"firewall:\n  "+firewall),
		)
		require.Error(t, err, name)
	}

	_, err := util.ParseSitesFromFiles(
		writeSite(
			t,
			"site-a.yml",
			"name: site-a\n"+requiredFields+"firewall:\n  services:\n    ssh:\n      from: [lan]\n",
		),
	)
	require.NoError(t, err)
}

// TestParseSitesInvalidSite names the file and the site for a site that fails its validation.
func TestParseSitesInvalidSite(t *testing.T) {
	_, err := util.ParseSitesFromFiles(writeSite(t, "site-a.yml", "name: site-a\n"))

	require.Error(t, err)
	assert.Contains(t, err.Error(), "site-a.yml")
	assert.Contains(t, err.Error(), `site "site-a"`)
	assert.Contains(t, err.Error(), "network: required")
}

// TestParseSitesUnknownField rejects a key the model does not know.
func TestParseSitesUnknownField(t *testing.T) {
	_, err := util.ParseSitesFromFiles(writeSite(t, "site-a.yml", "name: site-a\n"+requiredFields+"typo: 1\n"))
	require.Error(t, err)
}

// TestParseSitesBrokenSecondDocument reports a second document that is not YAML instead of ignoring it.
func TestParseSitesBrokenSecondDocument(t *testing.T) {
	_, err := util.ParseSitesFromFiles(writeSite(t, "site-a.yml", "name: site-a\n"+requiredFields+"---\n: : :\n\t["))
	require.Error(t, err)
}

// TestParseSitesRepositoryFiles checks that the site files of the repository and the site template are valid.
func TestParseSitesRepositoryFiles(t *testing.T) {
	sites, err := util.ParseSitesFromFiles("../../assets/sites")
	require.NoError(t, err)
	assert.NotEmpty(t, sites)

	template, err := os.ReadFile("../../assets/templates/site.yml")
	require.NoError(t, err)
	_, err = util.ParseSitesFromFiles(writeSite(t, "site.yml", string(template)))
	require.NoError(t, err)
}
