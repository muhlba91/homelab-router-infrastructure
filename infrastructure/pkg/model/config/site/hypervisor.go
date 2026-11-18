package site

// HypervisorConfig defines the libvirt/QEMU hypervisor module on the router.
type HypervisorConfig struct {
	// Enabled indicates whether the router runs the hypervisor module.
	Enabled *bool `yaml:"enabled,omitempty"`
}
