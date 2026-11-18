package site

// SystemConfig defines the system configuration (watchdog, garbage collection) for a site.
type SystemConfig struct {
	// Watchdog is the hardware watchdog timeout as a duration (e.g. "60s"; "0s" = off).
	Watchdog *string `yaml:"watchdog,omitempty"`
	// GC is the garbage collection configuration of the system generations.
	GC *GCConfig `yaml:"gc,omitempty"`
	// AutoReboot is the timer that reboots the router when the kernel, initrd or modules changed.
	AutoReboot *AutoRebootConfig `yaml:"autoReboot,omitempty"`
}

// AutoRebootConfig defines the automatic reboot of the router after a kernel, initrd or modules change.
type AutoRebootConfig struct {
	// Enabled indicates whether the router reboots by itself.
	Enabled *bool `yaml:"enabled,omitempty"`
	// Window is the time of the reboot check as a systemd OnCalendar expression (e.g. "Mon 04:00").
	Window *string `yaml:"window,omitempty"`
}

// GCConfig defines the garbage collection of the system generations.
type GCConfig struct {
	// OlderThan is the age (e.g. "7d") after which a generation is deleted.
	OlderThan *string `yaml:"olderThan,omitempty"`
	// Keep is the maximum number of generations kept, even if they are younger than OlderThan.
	Keep *int `yaml:"keep,omitempty"`
}
