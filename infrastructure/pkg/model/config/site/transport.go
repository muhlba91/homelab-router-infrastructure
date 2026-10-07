package site

// TransportConfig defines the transport configuration for a site.
type TransportConfig struct {
	// NetBird is the NetBird transport configuration for the site.
	NetBird *NetBirdConfig `yaml:"netbird,omitempty"`
}

// NetBirdConfig defines the NetBird transport configuration for a site.
type NetBirdConfig struct {
	// Enabled indicates whether NetBird is enabled for the site (default false).
	Enabled *bool `yaml:"enabled,omitempty"`
	// Port is the local WireGuard port (default 51820).
	Port *int `yaml:"port,omitempty"`
	// MTU is the MTU of the NetBird interface (default 1420).
	MTU *int `yaml:"mtu,omitempty"`
}
