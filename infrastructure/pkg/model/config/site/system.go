package site

// SystemConfig defines the system configuration (watchdog, garbage collection) for a site.
type SystemConfig struct {
	// Watchdog is the hardware watchdog timeout as a duration (e.g. "60s"; "0s" = off).
	Watchdog *string `yaml:"watchdog,omitempty"`
	// GC is the garbage collection configuration of the system generations.
	GC *GCConfig `yaml:"gc,omitempty"`
}

// GCConfig defines the garbage collection of the system generations.
type GCConfig struct {
	// OlderThan is the age (e.g. "7d") after which a generation is deleted.
	OlderThan *string `yaml:"olderThan,omitempty"`
	// Keep is the maximum number of generations kept, even if they are younger than OlderThan.
	Keep *int `yaml:"keep,omitempty"`
}
