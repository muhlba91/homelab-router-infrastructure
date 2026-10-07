package site

import "github.com/muhlba91/pulumi-shared-library/pkg/util/defaults"

// defaultEnabled is the default of Config.Enabled: a site is enabled explicitly.
const defaultEnabled = false

// defaultNetbirdEnabled is the default of NetBirdConfig.Enabled (the Nix default of transport.netbird.enable).
const defaultNetbirdEnabled = false

// defaultUPSEnabled is the default of UPSConfig.Enabled (the Nix default of hardware.ups.enable).
const defaultUPSEnabled = false

// Config defines Site-related configuration.
type Config struct {
	// Name is the name of the site: also its hostname and the name of its file ([<order>-]<name>.yml).
	Name string `yaml:"name"`
	// DeployOrder is the number a file name starts with (<order>-<name>.yml): the sites are deployed in ascending
	// order (sites without one last). Set from the file name, not part of the file.
	DeployOrder *int `yaml:"-"`
	// Enabled indicates whether the site may be deployed. Default false: a site is enabled explicitly, never by a
	// file that is still being written. A disabled site is still rendered and checked, but gets no generated keys
	// or secrets. Disabling a deployed site deletes them: after re-enabling it, the router still has the old deploy
	// key and host key, so the first deploy needs a static key and the new host key pushed by hand (or a reinstall).
	Enabled *bool `yaml:"enabled,omitempty"`
	// Hardware is the hardware configuration of the site.
	Hardware *HardwareConfig `yaml:"hardware"`
	// System is the system configuration (watchdog, garbage collection) of the site.
	System *SystemConfig `yaml:"system,omitempty"`
	// Network is the network configuration of the site.
	Network *NetworkConfig `yaml:"network"`
	// DHCP is the DHCP configuration of the site.
	DHCP *DHCPConfig `yaml:"dhcp"`
	// DNS is the DNS configuration of the site.
	DNS *DNSConfig `yaml:"dns,omitempty"`
	// Firewall is the firewall configuration of the site.
	Firewall *FirewallConfig `yaml:"firewall,omitempty"`
	// Security is the security configuration (CrowdSec) of the site.
	Security *SecurityConfig `yaml:"security,omitempty"`
	// Observability is the observability configuration (monitoring, logging) of the site.
	Observability *ObservabilityConfig `yaml:"observability,omitempty"`
	// Transport is the transport configuration of the site.
	Transport *TransportConfig `yaml:"transport,omitempty"`
	// BGP is the BGP configuration of the site.
	BGP *BGPConfig `yaml:"bgp"`
}

// IsEnabled reports whether the site is enabled (deployable); unset means disabled.
func (c *Config) IsEnabled() bool {
	return defaults.GetOrDefault(c.Enabled, defaultEnabled)
}

// UsesNetbird reports whether the site runs the NetBird underlay (transport.netbird.enabled).
func (c *Config) UsesNetbird() bool {
	return c.Transport != nil && c.Transport.NetBird != nil &&
		defaults.GetOrDefault(c.Transport.NetBird.Enabled, defaultNetbirdEnabled)
}

// UsesUPS reports whether the router has a UPS (hardware.ups.enabled).
func (c *Config) UsesUPS() bool {
	return c.Hardware != nil && c.Hardware.UPS != nil &&
		defaults.GetOrDefault(c.Hardware.UPS.Enabled, defaultUPSEnabled)
}
