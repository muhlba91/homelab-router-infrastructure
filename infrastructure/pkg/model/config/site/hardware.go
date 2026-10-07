package site

// HardwareConfig defines the hardware configuration for a site.
type HardwareConfig struct {
	// Profile is the hardware profile of the site: a file in nix/hardware/ (e.g. qemu: any x86_64 VM).
	Profile string `yaml:"profile"`
	// Disk is the install disk of the router (wiped by the first install).
	Disk string `yaml:"disk"`
	// UPS is the UPS attached to the router (NUT).
	UPS *UPSConfig `yaml:"ups,omitempty"`
}

// UPSConfig defines the UPS attached to the router: NUT reads it, serves it to the LAN and shuts the router down
// when the battery runs low. An enabled UPS gets a generated password (secrets/nut-password).
type UPSConfig struct {
	// Enabled indicates whether the router has a UPS. Default false.
	Enabled *bool `yaml:"enabled,omitempty"`
	// Name is the name of the UPS in NUT (what clients ask for).
	Name *string `yaml:"name,omitempty"`
	// Driver is the NUT driver of the UPS.
	Driver *string `yaml:"driver,omitempty"`
	// Port is the port of the UPS for the driver.
	Port *string `yaml:"port,omitempty"`
}
