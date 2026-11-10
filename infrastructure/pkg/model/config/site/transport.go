package site

// TransportConfig defines the transport configuration for a site.
type TransportConfig struct {
	// NetBird is the NetBird transport configuration for the site.
	NetBird *NetBirdConfig `yaml:"netbird,omitempty"`
}

// NetBirdConfig defines the NetBird transport configuration for a site.
type NetBirdConfig struct {
	// Enabled indicates whether NetBird is enabled for the site.
	Enabled *bool `yaml:"enabled,omitempty"`
	// Port is the local WireGuard port.
	Port *int `yaml:"port,omitempty"`
	// MTU is the MTU of the NetBird interface.
	MTU *int `yaml:"mtu,omitempty"`
}
