package site

// SecurityConfig defines the security configuration for a site.
type SecurityConfig struct {
	// CrowdSec is the CrowdSec configuration of the site.
	CrowdSec *CrowdSecConfig `yaml:"crowdsec,omitempty"`
}

// CrowdSecConfig defines the CrowdSec configuration (detection, community blocklist, firewall bouncer).
type CrowdSecConfig struct {
	// Enabled indicates whether CrowdSec runs on the router.
	Enabled *bool `yaml:"enabled,omitempty"`
	// BanDuration is how long a detected source stays banned (e.g. "4h").
	BanDuration *string `yaml:"banDuration,omitempty"`
}
