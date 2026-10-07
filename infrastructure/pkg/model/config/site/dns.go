package site

// DNSConfig defines the DNS configuration for a site.
type DNSConfig struct {
	// ConditionalForwards is a map of domain names to IP addresses for conditional DNS forwarding.
	ConditionalForwards map[string]string `yaml:"conditionalForwards,omitempty"`
	// ExtraRules is a list of AdGuard filtering rules of the site, added to the common ones.
	ExtraRules []string `yaml:"extraRules,omitempty"`
}
