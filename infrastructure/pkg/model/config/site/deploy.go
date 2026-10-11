package site

// DeployConfig defines how a site's router is deployed.
type DeployConfig struct {
	// Automated indicates whether CI deploys the router after every `pulumi up` on main (default false; only for an
	// enabled site). Off, the site keeps its keys and is deployed by hand only (`./router deploy`).
	Automated *bool `yaml:"automated,omitempty"`
}
