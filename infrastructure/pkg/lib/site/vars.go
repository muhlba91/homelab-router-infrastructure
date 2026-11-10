package site

import (
	"github.com/muhlba91/pulumi-shared-library/pkg/util/template"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/model/config/site"
	netbirdModel "github.com/muhlba91/homelab-router-infrastructure/pkg/model/netbird"
)

// varsTemplate is the template of the vars.nix file (Go text/template).
const varsTemplate = "./assets/vars.nix.j2"

// netbirdView is the part of the NetBird connection the template may use; the rest (the token) stays out of its
// reach.
type netbirdView struct {
	// Address is the URL of the NetBird management server.
	Address string
	// HubIP is the NetBird IPv4 address of the hub (its EVPN VTEP).
	HubIP string
}

// renderVars renders the vars.nix file of a site.
// site: The site configuration.
// sshKeys: The public SSH keys of the deploy user.
// hostKey: The public SSH host key of the router; empty for a disabled site.
// netbirdConfig: The NetBird connection of the core stack.
func renderVars(
	site *site.Config,
	sshKeys []string,
	hostKey string,
	netbirdConfig *netbirdModel.Config,
) (string, error) {
	return template.Render(varsTemplate, map[string]any{
		"Router":  site,
		"SSHKeys": sshKeys,
		"HostKey": hostKey,
		"Netbird": netbirdView{Address: netbirdConfig.Address, HubIP: netbirdConfig.HubIP},
	})
}
