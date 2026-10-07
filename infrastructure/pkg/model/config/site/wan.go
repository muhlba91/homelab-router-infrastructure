package site

// WANConfig defines the WAN configuration for a site.
type WANConfig struct {
	*InterfaceConfig `yaml:",inline"`

	// V4 is the IPv4 configuration for the site.
	V4 *WANIPConfig `yaml:"v4"`
	// V6 is the IPv6 configuration for the site.
	V6 *WANIPConfig `yaml:"v6,omitempty"`
	// VLAN is the VLAN ID for the WAN interface.
	VLAN *int `yaml:"vlan,omitempty"`
	// Shaping is the traffic shaping configuration of the WAN interface.
	Shaping *ShapingConfig `yaml:"shaping,omitempty"`
}

// ShapingConfig defines the traffic shaping (CAKE) of the WAN interface.
type ShapingConfig struct {
	// Upload is the rate the upload is shaped to (e.g. "45M"), slightly below the line's upload rate.
	Upload *string `yaml:"upload,omitempty"`
}

// WANIPConfig defines the WAN IP configuration for a site.
type WANIPConfig struct {
	*IPConfig `yaml:",inline"`

	// Method is the method of IP assignment: v4 "static" or "dhcp", v6 "static" or "dhcp6".
	Method string `yaml:"method"`
	// Gateway is the gateway for the site.
	Gateway *string `yaml:"gateway,omitempty"`
	// Announce indicates whether the static WAN network is announced in BGP and reachable from the other sites,
	// masqueraded to the WAN address (default false; IPv6 only for a ULA WAN), e.g. a transfer net to a hypervisor.
	Announce *bool `yaml:"announce,omitempty"`
}
