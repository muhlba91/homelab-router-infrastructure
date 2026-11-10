package site

import (
	"errors"
	"fmt"
	"maps"
	"slices"

	"github.com/muhlba91/pulumi-shared-library/pkg/util/defaults"
)

const (
	methodStatic = "static"
	policyStrict = "strict"
	// maxPrefixV4 and maxPrefixV6 are the longest prefix lengths of the address families.
	maxPrefixV4 = 32
	maxPrefixV6 = 128
)

// Validate checks what the vars.nix template relies on: the required sections and fields, the enumerated values and
// the dependencies between features. All problems are returned, joined; each names its field.
func (c *Config) Validate() error {
	var errs []error
	add := func(err error) {
		if err != nil {
			errs = append(errs, err)
		}
	}

	if c.Hardware == nil || c.Hardware.Profile == "" || c.Hardware.Disk == "" {
		add(errors.New("hardware: profile and disk are required"))
	}
	if c.Network == nil {
		add(errors.New("network: required"))
	} else {
		errs = append(errs, c.Network.validate()...)
	}
	if c.DHCP == nil || c.DHCP.V4 == nil || c.DHCP.V6 == nil {
		add(errors.New("dhcp: v4 and v6 pools are required"))
	} else {
		add(c.DHCP.validate())
	}
	if c.Firewall != nil {
		errs = append(errs, c.Firewall.validate()...)
	}
	if c.BGP != nil {
		errs = append(errs, c.validateBGP()...)
	}

	if err := errors.Join(errs...); err != nil {
		return fmt.Errorf("site %q: %w", c.Name, err)
	}

	return nil
}

// validate checks the network section.
func (n *NetworkConfig) validate() []error {
	var errs []error
	if n.Domain == "" {
		errs = append(errs, errors.New("network.domain: required"))
	}
	if n.TrustedNetworks == nil {
		errs = append(errs, errors.New("network.trustedNetworks: required"))
	}

	if n.WAN == nil {
		errs = append(errs, errors.New("network.wan: required"))
	} else {
		errs = append(errs, n.WAN.validate()...)
	}
	if n.LAN == nil {
		errs = append(errs, errors.New("network.lan: required"))
	} else {
		errs = append(errs, n.LAN.validate()...)
	}

	for i, r := range n.AdditionalRoutableNetworks {
		if r == nil || r.Prefix == "" || r.Anchor == "" {
			errs = append(errs, fmt.Errorf("network.additionalRoutableNetworks[%d]: prefix and anchor are required", i))
		}
	}
	for i, l := range n.Loopbacks {
		if l == nil || l.Address == "" {
			errs = append(errs, fmt.Errorf("network.loopbacks[%d]: address is required", i))
		}
	}

	return errs
}

// validate checks the WAN section.
func (w *WANConfig) validate() []error {
	var errs []error
	if w.MAC == "" || w.Interface == "" {
		errs = append(errs, errors.New("network.wan: mac and interface are required"))
	}
	if w.V4 == nil {
		errs = append(errs, errors.New("network.wan.v4: required"))
	} else {
		errs = append(errs, w.V4.validate("network.wan.v4", "dhcp", maxPrefixV4)...)
	}
	if w.V6 != nil {
		errs = append(errs, w.V6.validate("network.wan.v6", "dhcp6", maxPrefixV6)...)
	}

	return errs
}

// validate checks a WAN address configuration.
// field: The path of the field, for the errors.
// dynamic: The name of the dynamic method of the address family.
// maxPrefix: The longest prefix length of the address family.
func (w *WANIPConfig) validate(field, dynamic string, maxPrefix int) []error {
	switch w.Method {
	case dynamic:
		return nil
	case methodStatic:
		return validateAddress(field, &w.IPConfig, maxPrefix)
	default:
		return []error{fmt.Errorf("%s.method: %q is not %q or %q", field, w.Method, methodStatic, dynamic)}
	}
}

// validate checks the LAN section.
func (l *LANConfig) validate() []error {
	var errs []error
	if l.MAC == "" || l.Interface == "" {
		errs = append(errs, errors.New("network.lan: mac and interface are required"))
	}

	if l.V4 == nil {
		errs = append(errs, errors.New("network.lan.v4: required"))
	} else {
		errs = append(errs, validateAddress("network.lan.v4", &l.V4.IPConfig, maxPrefixV4)...)
		if l.V4.Network == "" {
			errs = append(errs, errors.New("network.lan.v4.network: required"))
		}
	}

	if l.V6 == nil {
		errs = append(errs, errors.New("network.lan.v6: required"))
	} else {
		errs = append(errs, validateAddress("network.lan.v6", &l.V6.IPConfig, maxPrefixV6)...)
		if l.V6.Network == "" || l.V6.Supernet == "" {
			errs = append(errs, errors.New("network.lan.v6: network and supernet are required"))
		}
	}

	return errs
}

// validateAddress checks that an address configuration has an address and a prefix length in range.
// field: The path of the field, for the errors.
// ip: The address configuration.
// maxPrefix: The longest prefix length of the address family.
func validateAddress(field string, ip *IPConfig, maxPrefix int) []error {
	var errs []error
	if ip.Address == nil || *ip.Address == "" {
		errs = append(errs, fmt.Errorf("%s.address: required", field))
	}
	if ip.Netmask == nil || *ip.Netmask < 0 || *ip.Netmask > maxPrefix {
		errs = append(errs, fmt.Errorf("%s.netmask: a prefix length from 0 to %d is required", field, maxPrefix))
	}

	return errs
}

// validate checks the DHCP pools and reservations.
func (d *DHCPConfig) validate() error {
	var errs []error
	if d.V4.Start == "" || d.V4.End == "" {
		errs = append(errs, errors.New("dhcp.v4: start and end are required"))
	}
	if d.V6.Start == "" || d.V6.End == "" {
		errs = append(errs, errors.New("dhcp.v6: start and end are required"))
	}
	for i, r := range d.Reservations {
		switch {
		case r == nil || r.Hostname == "":
			errs = append(errs, fmt.Errorf("dhcp.reservations[%d]: hostname is required", i))
		case r.V4 != nil && r.MAC == nil:
			errs = append(errs, fmt.Errorf("dhcp.reservations[%d] (%s): v4 needs a mac", i, r.Hostname))
		case r.V6 != nil && r.DUID == nil:
			errs = append(errs, fmt.Errorf("dhcp.reservations[%d] (%s): v6 needs a duid", i, r.Hostname))
		}
	}

	return errors.Join(errs...)
}

// validate checks the forwards and services.
func (f *FirewallConfig) validate() []error {
	var errs []error
	if f.Forwards != nil {
		for _, family := range []struct {
			name    string
			entries []*ForwardEntryConfig
		}{{"v4", f.Forwards.V4}, {"v6", f.Forwards.V6}} {
			for i, e := range family.entries {
				switch {
				case e == nil:
					errs = append(errs, fmt.Errorf("firewall.forwards.%s[%d]: must not be empty", family.name, i))
				case !slices.Contains([]string{"tcp", "udp"}, e.Proto):
					errs = append(
						errs,
						fmt.Errorf("firewall.forwards.%s[%d].proto: %q is not tcp or udp", family.name, i, e.Proto),
					)
				case len(e.Ports) == 0 || e.To == "":
					errs = append(
						errs,
						fmt.Errorf("firewall.forwards.%s[%d]: ports and to are required", family.name, i),
					)
				}
			}
		}
	}
	for _, name := range slices.Sorted(maps.Keys(f.Services)) {
		s := f.Services[name]
		if s == nil {
			errs = append(
				errs,
				fmt.Errorf("firewall.services.%s: must not be empty (omit it to keep the default)", name),
			)
		} else if s.Proto != nil && !slices.Contains([]string{"tcp", "udp", "both"}, *s.Proto) {
			errs = append(errs, fmt.Errorf("firewall.services.%s.proto: %q is not tcp, udp or both", name, *s.Proto))
		}
	}

	return errs
}

// validateBGP checks the BGP section and its dependencies on EVPN and NetBird.
func (c *Config) validateBGP() []error {
	var errs []error
	evpn := c.BGP.EVPN != nil && defaults.GetOrDefault(c.BGP.EVPN.Enabled, false)
	if evpn && !c.UsesNetbird() {
		errs = append(errs, errors.New("bgp.evpn: enabled needs transport.netbird.enabled"))
	}
	if c.BGP.ASN == 0 {
		errs = append(errs, errors.New("bgp.asn: required"))
	}
	for i, p := range c.BGP.Peers {
		errs = append(errs, p.validate(i, evpn)...)
	}

	return errs
}

// validate checks a BGP peer.
// i: The index of the peer, for the errors.
// evpn: Whether EVPN is enabled on the site.
func (p *BGPPeerConfig) validate(i int, evpn bool) []error {
	if p == nil || p.Name == "" || p.Address == "" || p.RemoteASN == 0 {
		return []error{fmt.Errorf("bgp.peers[%d]: name, address and remoteAs are required", i)}
	}

	var errs []error
	policies := []string{policyStrict, "allow-all", "deny-all"}
	for _, f := range []struct {
		name   string
		policy *string
	}{{"inPolicy", p.InPolicy}, {"outPolicy", p.OutPolicy}} {
		if f.policy != nil && !slices.Contains(policies, *f.policy) {
			errs = append(
				errs,
				fmt.Errorf("bgp.peers[%d] (%s).%s: %q is not one of %v", i, p.Name, f.name, *f.policy, policies),
			)
		}
	}
	if defaults.GetOrDefault(p.Transit, false) {
		if !evpn {
			errs = append(errs, fmt.Errorf("bgp.peers[%d] (%s).transit: needs bgp.evpn.enabled", i, p.Name))
		}
		if p.InPolicy != nil && *p.InPolicy != policyStrict {
			errs = append(
				errs,
				fmt.Errorf("bgp.peers[%d] (%s).transit: needs the %s inPolicy", i, p.Name, policyStrict),
			)
		}
	}

	return errs
}
