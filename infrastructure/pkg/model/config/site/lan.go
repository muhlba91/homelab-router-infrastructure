package site

// LANConfig defines the LAN configuration for a site.
type LANConfig struct {
	*InterfaceConfig `yaml:",inline"`

	// V4 is the IPv4 configuration for the site.
	V4 *LANIPv4Config `yaml:"v4"`
	// V6 is the IPv6 configuration for the site.
	V6 *LANIPv6Config `yaml:"v6"`
}

// LANIPConfig defines the LAN IP configuration for a site.
type LANIPConfig struct {
	*IPConfig `yaml:",inline"`

	// Network is the network associated with the LAN IP configuration for the site.
	Network string `yaml:"network"`
}

// LANIPv4Config defines the LAN IPv4 configuration for a site.
type LANIPv4Config struct {
	*LANIPConfig `yaml:",inline"`
}

// LANIPv6Config defines the LAN IPv6 configuration for a site.
type LANIPv6Config struct {
	*LANIPConfig `yaml:",inline"`

	// Public indicates whether the LAN prefix is publicly routable: no NAT66, and it is not announced in BGP.
	Public bool `yaml:"public"`
	// Supernet is the prefix covering the LANs behind this router (the NAT66 source range).
	Supernet string `yaml:"supernet"`
}
