package netbird

// Config defines the NetBird connection exported by the core infrastructure stack (output "netbird").
type Config struct {
	// Address is the URL of the NetBird management server.
	Address string
	// PAT is the personal access token for the NetBird API (secret).
	PAT string
	// HubIP is the NetBird IPv4 address of the hub (its EVPN VTEP).
	HubIP string
	// BackboneGroup is the ID of the NetBird group the site routers join.
	BackboneGroup string
}
