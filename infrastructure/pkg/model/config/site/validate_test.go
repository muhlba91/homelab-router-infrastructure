package site_test

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"gopkg.in/yaml.v3"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/model/config/site"
)

// validSite is a site with every required field and nothing else.
const validSite = `
name: site-a
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
`

func parse(t *testing.T) *site.Config {
	t.Helper()

	var c site.Config
	require.NoError(t, yaml.Unmarshal([]byte(validSite), &c))
	return &c
}

func ptr[T any](v T) *T { return &v }

func TestValidateValid(t *testing.T) {
	require.NoError(t, parse(t).Validate())
}

func TestValidate(t *testing.T) {
	peer := func(c *site.Config, p *site.BGPPeerConfig) {
		c.BGP = &site.BGPConfig{ASN: 64512, Peers: []*site.BGPPeerConfig{p}}
	}
	cases := map[string]struct {
		mutate func(c *site.Config)
		want   string
	}{
		"no hardware":     {func(c *site.Config) { c.Hardware = nil }, "hardware"},
		"no disk":         {func(c *site.Config) { c.Hardware.Disk = "" }, "hardware"},
		"no network":      {func(c *site.Config) { c.Network = nil }, "network: required"},
		"no domain":       {func(c *site.Config) { c.Network.Domain = "" }, "network.domain"},
		"no wan":          {func(c *site.Config) { c.Network.WAN = nil }, "network.wan: required"},
		"no wan mac":      {func(c *site.Config) { c.Network.WAN.MAC = "" }, "network.wan: mac"},
		"no wan v4":       {func(c *site.Config) { c.Network.WAN.V4 = nil }, "network.wan.v4"},
		"bad wan method":  {func(c *site.Config) { c.Network.WAN.V4.Method = "pppoe" }, "network.wan.v4.method"},
		"v6 dhcp for v4":  {func(c *site.Config) { c.Network.WAN.V4.Method = "dhcp6" }, "network.wan.v4.method"},
		"static v4 no ip": {func(c *site.Config) { c.Network.WAN.V4.Method = "static" }, "network.wan.v4.address"},
		"static v4 mask": {func(c *site.Config) {
			c.Network.WAN.V4 = &site.WANIPConfig{
				Method:   "static",
				IPConfig: site.IPConfig{Address: ptr("192.0.2.2"), Netmask: ptr(33)},
			}
		}, "network.wan.v4.netmask"},
		"bad wan v6 method": {
			func(c *site.Config) { c.Network.WAN.V6 = &site.WANIPConfig{Method: "dhcp"} },
			"network.wan.v6.method",
		},
		"no lan":            {func(c *site.Config) { c.Network.LAN = nil }, "network.lan: required"},
		"no lan v4":         {func(c *site.Config) { c.Network.LAN.V4 = nil }, "network.lan.v4"},
		"no lan v4 address": {func(c *site.Config) { c.Network.LAN.V4.Address = nil }, "network.lan.v4.address"},
		"no lan v4 netmask": {func(c *site.Config) { c.Network.LAN.V4.Netmask = nil }, "network.lan.v4.netmask"},
		"no lan v6":         {func(c *site.Config) { c.Network.LAN.V6 = nil }, "network.lan.v6"},
		"no supernet":       {func(c *site.Config) { c.Network.LAN.V6.Supernet = "" }, "supernet"},
		"no trusted":        {func(c *site.Config) { c.Network.TrustedNetworks = nil }, "trustedNetworks"},
		"no dhcp":           {func(c *site.Config) { c.DHCP = nil }, "dhcp"},
		"no dhcp v6":        {func(c *site.Config) { c.DHCP.V6 = nil }, "dhcp"},
		"empty pool":        {func(c *site.Config) { c.DHCP.V4.End = "" }, "dhcp.v4"},
		"reservation v4 without mac": {func(c *site.Config) {
			c.DHCP.Reservations = []*site.DHCPReservation{{Hostname: "h", V4: ptr("10.0.0.5")}}
		}, "needs a mac"},
		"reservation v6 without duid": {func(c *site.Config) {
			c.DHCP.Reservations = []*site.DHCPReservation{{Hostname: "h", V6: ptr("fd00::5")}}
		}, "needs a duid"},
		"nil reservation": {
			func(c *site.Config) { c.DHCP.Reservations = []*site.DHCPReservation{nil} },
			"dhcp.reservations[0]",
		},
		"nil loopback": {func(c *site.Config) { c.Network.Loopbacks = []*site.LoopbackConfig{nil} }, "loopbacks[0]"},
		"nil routable": {func(c *site.Config) {
			c.Network.AdditionalRoutableNetworks = []*site.AdditionalRoutableNetworkConfig{nil}
		}, "additionalRoutableNetworks[0]"},
		"bad forward proto": {func(c *site.Config) {
			c.Firewall = &site.FirewallConfig{Forwards: &site.ForwardConfig{V4: []*site.ForwardEntryConfig{
				{Proto: "icmp", Ports: []int{1}, To: "10.0.0.2"},
			}}}
		}, "firewall.forwards.v4[0].proto"},
		"nil forward": {func(c *site.Config) {
			c.Firewall = &site.FirewallConfig{Forwards: &site.ForwardConfig{V6: []*site.ForwardEntryConfig{nil}}}
		}, "firewall.forwards.v6[0]"},
		"nil service": {func(c *site.Config) {
			c.Firewall = &site.FirewallConfig{Services: map[string]*site.ServiceConfig{"ssh": nil}}
		}, "firewall.services.ssh"},
		"bad service proto": {func(c *site.Config) {
			c.Firewall = &site.FirewallConfig{Services: map[string]*site.ServiceConfig{"x": {Proto: ptr("sctp")}}}
		}, "firewall.services.x.proto"},
		"no asn":          {func(c *site.Config) { c.BGP = &site.BGPConfig{} }, "bgp.asn"},
		"peer incomplete": {func(c *site.Config) { peer(c, &site.BGPPeerConfig{Name: "p"}) }, "bgp.peers[0]"},
		"bad peer policy": {func(c *site.Config) {
			peer(c, &site.BGPPeerConfig{Name: "p", Address: "10.0.0.9", RemoteASN: 1, InPolicy: ptr("any")})
		}, "inPolicy"},
		"evpn without netbird": {func(c *site.Config) {
			c.BGP = &site.BGPConfig{ASN: 1, EVPN: &site.EVPNConfig{Enabled: ptr(true)}}
		}, "bgp.evpn"},
		"transit without evpn": {func(c *site.Config) {
			peer(c, &site.BGPPeerConfig{Name: "p", Address: "10.0.0.9", RemoteASN: 1, Transit: ptr(true)})
		}, "transit"},
		"transit without strict": {func(c *site.Config) {
			c.Transport = &site.TransportConfig{NetBird: &site.NetBirdConfig{Enabled: ptr(true)}}
			c.BGP = &site.BGPConfig{
				ASN:  1,
				EVPN: &site.EVPNConfig{Enabled: ptr(true)},
				Peers: []*site.BGPPeerConfig{
					{Name: "p", Address: "10.0.0.9", RemoteASN: 1, Transit: ptr(true), InPolicy: ptr("allow-all")},
				},
			}
		}, "strict"},
	}

	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			c := parse(t)
			tc.mutate(c)

			err := c.Validate()
			require.Error(t, err)
			assert.Contains(t, err.Error(), tc.want)
			assert.Contains(t, err.Error(), `site "site-a"`)
		})
	}
}

func TestValidateEVPNWithTransit(t *testing.T) {
	c := parse(t)
	c.Transport = &site.TransportConfig{NetBird: &site.NetBirdConfig{Enabled: ptr(true)}}
	c.BGP = &site.BGPConfig{
		ASN:  1,
		EVPN: &site.EVPNConfig{Enabled: ptr(true)},
		Peers: []*site.BGPPeerConfig{
			{Name: "p", Address: "10.0.0.9", RemoteASN: 1, Transit: ptr(true), InPolicy: ptr("strict")},
		},
	}

	require.NoError(t, c.Validate())
}

func TestValidateStaticWAN(t *testing.T) {
	c := parse(t)
	c.Network.WAN.V4 = &site.WANIPConfig{
		Method:   "static",
		IPConfig: site.IPConfig{Address: ptr("192.0.2.2"), Netmask: ptr(24)},
	}
	c.Network.WAN.V6 = &site.WANIPConfig{Method: "dhcp6"}

	require.NoError(t, c.Validate())
}

func TestUses(t *testing.T) {
	assert.False(t, (&site.Config{}).UsesNetbird())
	assert.False(t, (&site.Config{}).UsesUPS())
	assert.False(t, (&site.Config{}).UsesCrowdSecConsole())

	c := &site.Config{
		Transport: &site.TransportConfig{NetBird: &site.NetBirdConfig{}},
		Hardware:  &site.HardwareConfig{UPS: &site.UPSConfig{}},
		Security:  &site.SecurityConfig{CrowdSec: &site.CrowdSecConfig{Console: &site.CrowdSecConsoleConfig{}}},
	}
	assert.False(t, c.UsesNetbird(), "enabled defaults to false")
	assert.False(t, c.UsesUPS(), "enabled defaults to false")
	assert.False(t, c.UsesCrowdSecConsole(), "console defaults to false")

	c.Transport.NetBird.Enabled = ptr(true)
	c.Hardware.UPS.Enabled = ptr(true)
	c.Security.CrowdSec.Console.Enabled = ptr(true)
	assert.True(t, c.UsesNetbird())
	assert.True(t, c.UsesUPS())
	assert.True(t, c.UsesCrowdSecConsole(), "CrowdSec defaults to enabled")

	c.Security.CrowdSec.Enabled = ptr(false)
	assert.False(t, c.UsesCrowdSecConsole(), "console needs CrowdSec")
}
