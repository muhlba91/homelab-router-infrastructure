package site

// NetworkConfig defines the network configuration for a site.
type NetworkConfig struct {
	// Domain is the domain of the site.
	Domain string `yaml:"domain"`
	// WAN is the WAN network configuration (required).
	WAN *WANConfig `yaml:"wan"`
	// LAN is the LAN network configuration (required).
	LAN *LANConfig `yaml:"lan"`
	// ManagementAddress is the address (or name) used to manage the router; unset: the LAN IPv4 address.
	ManagementAddress *string `yaml:"managementAddress,omitempty"`
	// TrustedNetworks are the networks trusted by the router (required).
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
	// MAC is the MAC address of the NIC; the interface is named after it.
	MAC string `yaml:"mac"`
	// Interface is the name the NIC gets.
	Interface string `yaml:"interface"`
}

// IPConfig defines an interface address.
type IPConfig struct {
	// Address is the IP address (without prefix length).
	Address *string `yaml:"address,omitempty"`
	// Netmask is the prefix length of the address (e.g. 24), not a dotted mask.
	Netmask *int `yaml:"netmask,omitempty"`
}

// TrustedNetworksConfig defines the trusted networks configuration for a site.
type TrustedNetworksConfig struct {
	// V4 is the list of trusted IPv4 networks.
	V4 []string `yaml:"v4"`
	// V6 is the list of trusted IPv6 networks.
	V6 []string `yaml:"v6"`
	// WAN indicates whether the trusted networks are accepted on the WAN interface too; only for a WAN that is
	// itself a private network of ours (e.g. a transfer net), never for an internet WAN.
	WAN *bool `yaml:"wan,omitempty"`
}

// AdditionalRoutableNetworkConfig defines an additional routable network for a site.
type AdditionalRoutableNetworkConfig struct {
	// Prefix is the network prefix of the additional routable network.
	Prefix string `yaml:"prefix"`
	// Anchor is the address inside Prefix the router answers for.
	Anchor string `yaml:"anchor"`
}

// LoopbackConfig defines an extra host address on the loopback of a site.
type LoopbackConfig struct {
	// Address is the IPv4 or IPv6 host address (without prefix length).
	Address string `yaml:"address"`
	// Announce indicates whether the address is announced in BGP.
	Announce *bool `yaml:"announce,omitempty"`
}
