package site

// BGPConfig defines the BGP configuration for a site.
type BGPConfig struct {
	// Enabled indicates whether BGP runs on the site (default true; EVPN needs it).
	Enabled *bool `yaml:"enabled,omitempty"`
	// ASN is the Autonomous System Number for the site.
	ASN int `yaml:"asn"`
	// Peers is a list of BGP peers for the site.
	Peers []*BGPPeerConfig `yaml:"peers,omitempty"`
	// EVPN is the EVPN configuration for the site.
	EVPN *EVPNConfig `yaml:"evpn,omitempty"`
}

// BGPPeerConfig defines the configuration for a BGP peer.
type BGPPeerConfig struct {
	// Name is the name of the BGP peer.
	Name string `yaml:"name"`
	// Address is the IP address of the BGP peer.
	Address string `yaml:"address"`
	// RemoteASN is the Autonomous System Number of the BGP peer.
	RemoteASN int `yaml:"remoteAs"`
	// Interface is the interface used to connect to the BGP peer.
	Interface *string `yaml:"interface,omitempty"`
	// BFD indicates whether BFD is enabled for the BGP peer.
	BFD *bool `yaml:"bfd,omitempty"`
	// DisableConnectedCheck indicates whether to disable the connected check for the BGP peer.
	DisableConnectedCheck *bool `yaml:"disableConnectedCheck,omitempty"`
	// NextHopSelf indicates whether to set the next hop to self for routes advertised to the BGP peer.
	NextHopSelf *bool `yaml:"nextHopSelf,omitempty"`
	// Multihop is the eBGP multihop TTL for a peer that is not directly connected.
	Multihop *int `yaml:"multihop,omitempty"`
	// V4 indicates whether IPv4 unicast is activated on the BGP peer (default true).
	V4 *bool `yaml:"v4,omitempty"`
	// V6 indicates whether IPv6 unicast is activated on the BGP peer (default true).
	V6 *bool `yaml:"v6,omitempty"`
	// InPolicy is the inbound policy for routes received from the BGP peer ("strict", "allow-all", "deny-all").
	InPolicy *string `yaml:"inPolicy,omitempty"`
	// OutPolicy is the outbound policy for routes advertised to the BGP peer ("strict", "allow-all", "deny-all").
	OutPolicy *string `yaml:"outPolicy,omitempty"`
	// Transit indicates whether every route accepted from the BGP peer is passed on to the other sites through
	// EVPN (default false; needs the "strict" InPolicy and EVPN; never for a peer that is itself a site).
	Transit *bool `yaml:"transit,omitempty"`
}

// EVPNConfig defines the EVPN configuration for a site.
type EVPNConfig struct {
	// Enabled indicates whether EVPN is enabled for the site (default false).
	Enabled *bool `yaml:"enabled,omitempty"`
}
