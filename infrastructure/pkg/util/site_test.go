package util_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/util"
)

// writeSites writes one site file per entry (file name -> site name) into a new directory.
func writeSites(t *testing.T, files map[string]string) string {
	t.Helper()

	dir := t.TempDir()
	for file, name := range files {
		require.NoError(t, os.WriteFile(filepath.Join(dir, file), []byte("name: "+name+"\n"), 0o600))
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
		_, err := util.ParseSitesFromFiles(writeSite(t, name+".yml", "name: "+name+"\n"))
		require.Error(t, err, name)
	}
}

// TestParseSitesMultipleDocuments rejects a file with a second YAML document.
func TestParseSitesMultipleDocuments(t *testing.T) {
	_, err := util.ParseSitesFromFiles(writeSite(t, "site-a.yml", "name: site-a\n---\nenabled: true\n"))
	require.Error(t, err)
}

// TestParseSitesEmptyLists rejects empty lists that would render like omitted ones (open instead of closed).
func TestParseSitesEmptyLists(t *testing.T) {
	for name, firewall := range map[string]string{
		"forward from":  "forwards:\n    v4:\n      - proto: tcp\n        ports: [80]\n        to: 10.0.0.2\n        from: []\n",
		"service from":  "services:\n    ssh:\n      from: []\n",
		"service ports": "services:\n    ssh:\n      ports: []\n",
	} {
		_, err := util.ParseSitesFromFiles(writeSite(t, "site-a.yml", "name: site-a\nfirewall:\n  "+firewall))
		require.Error(t, err, name)
	}

	_, err := util.ParseSitesFromFiles(
		writeSite(t, "site-a.yml", "name: site-a\nfirewall:\n  services:\n    ssh:\n      from: [lan]\n"),
	)
	require.NoError(t, err)
}
