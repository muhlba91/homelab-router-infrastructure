package site

// ObservabilityConfig defines the observability configuration (monitoring, logging) for a site.
type ObservabilityConfig struct {
	// Monitoring is the monitoring configuration (Prometheus exporters).
	Monitoring *MonitoringConfig `yaml:"monitoring,omitempty"`
	// Logging is the logging configuration (log shipping).
	Logging *LoggingConfig `yaml:"logging,omitempty"`
}

// MonitoringConfig defines the monitoring configuration for a site.
type MonitoringConfig struct {
	// Prometheus is the configuration of the Prometheus exporters.
	Prometheus *PrometheusConfig `yaml:"prometheus,omitempty"`
}

// PrometheusConfig defines the Prometheus exporters of a site, scraped from outside.
type PrometheusConfig struct {
	// Enabled indicates whether the exporters run (their ports are opened for lan and trusted).
	Enabled *bool `yaml:"enabled,omitempty"`
	// Exporters is the list of exporters ("node", "kea", "frr", "smartctl", "crowdsec", "nut").
	Exporters []string `yaml:"exporters,omitempty"`
}

// LoggingConfig defines the logging configuration for a site.
type LoggingConfig struct {
	// Vector is the configuration of the log shipping with Vector.
	Vector *VectorConfig `yaml:"vector,omitempty"`
}

// VectorConfig defines the shipping of the journal to a central Vector.
type VectorConfig struct {
	// Enabled indicates whether the journal is shipped.
	Enabled *bool `yaml:"enabled,omitempty"`
	// Address is the host:port of the receiving Vector (its "vector" source).
	Address *string `yaml:"address,omitempty"`
}
