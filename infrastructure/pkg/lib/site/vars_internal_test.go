package site

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	netbirdModel "github.com/muhlba91/homelab-router-infrastructure/pkg/model/netbird"
	"github.com/muhlba91/homelab-router-infrastructure/pkg/util"
)

// siteFile is a minimal site file using NetBird and EVPN (the features that render the NetBird connection).
const siteFile = `name: site-a
hardware: {profile: qemu, disk: /dev/sda}
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
transport:
  netbird: {enabled: true}
bgp:
  asn: 64923
  evpn: {enabled: true}
`

// optionalSiteFile is siteFile with every optional setting of the WAN, LAN, firewall, system and hardware that is
// rendered only when set.
const optionalSiteFile = `name: site-a
hardware:
  profile: qemu
  disk: /dev/sda
  kernelParams: ["console=ttyS0,115200", "quiet"]
system:
  autoReboot: {enabled: true, window: "Sun 03:00"}
firewall:
  hairpin: true
network:
  domain: a.example
  wan:
    mac: "00:00:00:00:00:01"
    interface: wan0
    v4: {method: static, address: 192.0.2.2, netmask: 32, gateway: 192.0.2.1, onLink: true}
    v6: {method: static, address: "2001:db8::2", netmask: 128, gateway: "fe80::1", onLink: true}
  lan:
    mac: "00:00:00:00:00:02"
    interface: lan0
    bridge: true
    v4: {address: 10.0.0.1, netmask: 24, network: 10.0.0.0}
    v6: {address: "fd00::1", netmask: 64, network: "fd00::", supernet: "fd00::/48"}
  trustedNetworks: {}
dhcp:
  v4: {start: 10.0.0.10, end: 10.0.0.20}
  v6: {start: "fd00::10", end: "fd00::20"}
`

// renderTestVars renders the minimal site in a directory holding a copy of the assets (the template path is
// relative).
func renderTestVars(t *testing.T, sshKeys []string, hostKey string) string {
	t.Helper()

	return renderSiteVars(t, siteFile, sshKeys, hostKey)
}

// renderSiteVars renders a site file in a directory holding a copy of the assets (the template path is relative).
func renderSiteVars(t *testing.T, content string, sshKeys []string, hostKey string) string {
	t.Helper()

	assets, err := filepath.Abs("../../../assets")
	require.NoError(t, err)
	dir := t.TempDir()
	require.NoError(t, os.CopyFS(filepath.Join(dir, "assets"), os.DirFS(assets)))
	t.Chdir(dir)

	sitesDir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(sitesDir, "site-a.yml"), []byte(content), 0o600))
	sites, err := util.ParseSitesFromFiles(sitesDir)
	require.NoError(t, err)
	require.Len(t, sites, 1)

	vars, err := renderVars(
		sites[0],
		sshKeys,
		hostKey,
		&netbirdModel.Config{Address: "https://netbird.example.org:443", HubIP: "10.253.0.1", PAT: "secret-token"},
	)
	require.NoError(t, err)
	return vars
}

// TestRenderVars renders the SSH keys, the host key and the NetBird connection, and never the NetBird token.
func TestRenderVars(t *testing.T) {
	vars := renderTestVars(t, []string{"ssh-ed25519 AAAA key-one"}, "ssh-ed25519 BBBB host")

	assert.Contains(t, vars, "ssh-ed25519 AAAA key-one")
	assert.Contains(t, vars, "ssh-ed25519 BBBB host")
	assert.Contains(t, vars, "https://netbird.example.org:443")
	assert.Contains(t, vars, "10.253.0.1")
	assert.NotContains(t, vars, "secret-token")
}

// TestRenderVarsWithoutHostKey leaves the host key out for a site that has none (a disabled site).
func TestRenderVarsWithoutHostKey(t *testing.T) {
	vars := renderTestVars(t, nil, "")

	assert.NotContains(t, vars, "hostKey")
}

// TestRenderVarsOptionalSettings renders the optional WAN, LAN, firewall, system and hardware settings.
func TestRenderVarsOptionalSettings(t *testing.T) {
	vars := renderSiteVars(t, optionalSiteFile, nil, "")

	assert.Equal(t, 2, strings.Count(vars, "onLink = true;"))
	assert.Contains(t, vars, "bridge = true;")
	assert.Contains(t, vars, "firewall.hairpin = true;")
	assert.Contains(t, vars, "system.autoReboot.enable = true;")
	assert.Contains(t, vars, `system.autoReboot.window = "Sun 03:00";`)
	assert.Contains(t, vars, `kernelParams = [ "console=ttyS0,115200" "quiet" ];`)
}

// TestRenderVarsWithoutOptionalSettings renders none of the optional keys for a site that does not set them.
func TestRenderVarsWithoutOptionalSettings(t *testing.T) {
	vars := renderTestVars(t, nil, "")

	for _, key := range []string{"onLink", "bridge", "hairpin", "autoReboot", "kernelParams"} {
		assert.NotContains(t, vars, key)
	}
}
