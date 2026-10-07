package site

// NetworkConfig defines the network configuration for a site.
type NetworkConfig struct {
	// Domain is the domain of the site.
	Domain string `yaml:"domain"`
	// WAN is the WAN network configuration of the site.
	WAN *WANConfig `yaml:"wan"`
	// LAN is the LAN network configuration of the site.
	LAN *LANConfig `yaml:"lan"`
	// ManagementAddress is the address (or name) used to manage the router (default: the LAN IPv4 address).
	ManagementAddress *string `yaml:"managementAddress,omitempty"`
	// TrustedNetworks is the list of trusted networks for the site.
	TrustedNetworks *TrustedNetworksConfig `yaml:"trustedNetworks"`
	// AdditionalRoutableNetworks is the list of additional routable networks for the site (only IPv6): public
	// prefixes routed to the site, anchored on the router and announced in BGP. Rendered as the Nix option
	// router.publicV6.
	AdditionalRoutableNetworks []*AdditionalRoutableNetworkConfig `yaml:"additionalRoutableNetworks,omitempty"`
	// Loopbacks is the list of extra host addresses on the loopback of the site.
	Loopbacks []*LoopbackConfig `yaml:"loopbacks,omitempty"`
}

// InterfaceConfig defines the interface configuration for a site.
type InterfaceConfig struct {
	// MAC is the MAC address of the site.
	MAC string `yaml:"mac"`
	// Interface is the network interface of the site.
	Interface string `yaml:"interface"`
}

// IPConfig defines the IP configuration for a site.
type IPConfig struct {
	// Address is the IP address of the site.
	Address *string `yaml:"address,omitempty"`
	// Netmask is the subnet mask of the site.
	Netmask *int `yaml:"netmask,omitempty"`
}

// TrustedNetworksConfig defines the trusted networks configuration for a site.
type TrustedNetworksConfig struct {
	// V4 is the list of trusted IPv4 networks for the site.
	V4 []string `yaml:"v4"`
	// V6 is the list of trusted IPv6 networks for the site.
	V6 []string `yaml:"v6"`
	// WAN indicates whether the trusted networks are accepted on the WAN interface too (default false); only for a
	// WAN that is itself a private network of ours (e.g. a transfer net), never for an internet WAN.
	WAN *bool `yaml:"wan,omitempty"`
}

// AdditionalRoutableNetworkConfig defines an additional routable network for a site.
type AdditionalRoutableNetworkConfig struct {
	// Prefix is the network prefix of the additional routable network.
	Prefix string `yaml:"prefix"`
	// Anchor is the anchor address of the additional routable network.
	Anchor string `yaml:"anchor"`
}

// LoopbackConfig defines an extra host address on the loopback of a site.
type LoopbackConfig struct {
	// Address is the IPv4 or IPv6 host address (without prefix length).
	Address string `yaml:"address"`
	// Announce indicates whether the address is announced in BGP (default true).
	Announce *bool `yaml:"announce,omitempty"`
}
