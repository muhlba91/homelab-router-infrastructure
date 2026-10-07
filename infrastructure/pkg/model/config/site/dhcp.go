package site

// DHCPConfig defines the DHCP configuration for a site.
type DHCPConfig struct {
	// V4 is the IPv4 address pool for DHCP.
	V4 *DHCPPool `yaml:"v4"`
	// V6 is the IPv6 address pool for DHCP.
	V6 *DHCPPool `yaml:"v6"`
	// Reservations is a list of DHCP reservations for the site.
	Reservations []*DHCPReservation `yaml:"reservations,omitempty"`
}

// DHCPPool defines a DHCP address pool (an inclusive range).
type DHCPPool struct {
	// Start is the first address of the pool.
	Start string `yaml:"start"`
	// End is the last address of the pool.
	End string `yaml:"end"`
}

// DHCPReservation defines a DHCP reservation for a specific device.
type DHCPReservation struct {
	// Hostname is the hostname associated with the reservation.
	Hostname string `yaml:"hostname"`
	// MAC is the reserved MAC address for the device (required with V4).
	MAC *string `yaml:"mac,omitempty"`
	// DUID is the reserved DUID for the device (required with V6).
	DUID *string `yaml:"duid,omitempty"`
	// V4 is the reserved IPv4 address for the device.
	V4 *string `yaml:"v4,omitempty"`
	// V6 is the reserved IPv6 address for the device.
	V6 *string `yaml:"v6,omitempty"`
}
