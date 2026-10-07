package site

// FirewallConfig defines the firewall configuration for a site.
type FirewallConfig struct {
	// Forwards is the port forwarding configuration for the site.
	Forwards *ForwardConfig `yaml:"forwards,omitempty"`
	// Services overrides fields of the default router services or adds new ones.
	Services map[string]*ServiceConfig `yaml:"services,omitempty"`
	// ExtraInputRules are raw nftables rules at the end of the input chain.
	ExtraInputRules *string `yaml:"extraInputRules,omitempty"`
	// ExtraForwardRules are raw nftables rules at the end of the forward chain.
	ExtraForwardRules *string `yaml:"extraForwardRules,omitempty"`
	// LogDrops is the logging of the connections from the WAN that are dropped.
	LogDrops *LogDropsConfig `yaml:"logDrops,omitempty"`
}

// LogDropsConfig defines the rate-limited logging of the connections from the WAN that are dropped.
type LogDropsConfig struct {
	// Enabled indicates whether dropped connections are logged.
	Enabled *bool `yaml:"enabled,omitempty"`
	// Rate is the rate limit of the log per chain (e.g. "5/second").
	Rate *string `yaml:"rate,omitempty"`
	// Burst is the burst (packets) of the rate limit.
	Burst *int `yaml:"burst,omitempty"`
}

// ForwardConfig defines the port forwarding configuration for a site.
type ForwardConfig struct {
	// V4 is the IPv4 port forwarding configuration for the site.
	V4 []*ForwardEntryConfig `yaml:"v4,omitempty"`
	// V6 is the IPv6 port forwarding configuration for the site (to ULA hosts behind NAT66).
	V6 []*ForwardEntryConfig `yaml:"v6,omitempty"`
}

// ForwardEntryConfig defines the configuration for a single port forwarding entry.
type ForwardEntryConfig struct {
	// Proto is the protocol used for the port forwarding ("tcp" or "udp").
	Proto string `yaml:"proto"`
	// Ports is the list of ports to be forwarded.
	Ports []int `yaml:"ports"`
	// To is the destination address to which the ports will be forwarded.
	To string `yaml:"to"`
	// From is the list of source addresses or networks allowed to use the forward (default: everyone).
	From []string `yaml:"from,omitempty"`
}

// ServiceConfig defines a service on the router itself; unset fields keep the default service's values.
type ServiceConfig struct {
	// Enabled indicates whether the service is open.
	Enabled *bool `yaml:"enabled,omitempty"`
	// Proto is the protocol of the service ("tcp", "udp" or "both").
	Proto *string `yaml:"proto,omitempty"`
	// Ports is the list of ports of the service.
	Ports []int `yaml:"ports,omitempty"`
	// From is the list of zones that may connect ("lan", "mesh", "trusted", "wan").
	From []string `yaml:"from,omitempty"`
}
