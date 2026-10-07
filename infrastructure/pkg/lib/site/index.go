package site

import (
	"fmt"
	"path"
	"slices"
	"strings"

	nbProvider "github.com/KitStream/netbird-pulumi-provider/sdk/go/netbird"
	"github.com/muhlba91/pulumi-shared-library/pkg/lib/random"
	"github.com/muhlba91/pulumi-shared-library/pkg/lib/tls"
	tlsProv "github.com/pulumi/pulumi-tls/sdk/v5/go/tls"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/lib/config"
	"github.com/muhlba91/homelab-router-infrastructure/pkg/lib/netbird"
	"github.com/muhlba91/homelab-router-infrastructure/pkg/model/config/site"
	netbirdModel "github.com/muhlba91/homelab-router-infrastructure/pkg/model/netbird"
)

// passwordLength is the length of the generated passwords (letters and digits only).
const passwordLength = 32

// Data holds the generated resources and files of a site.
type Data struct {
	// DeployKey is the SSH key pair of the deploy user of the site; nil for a disabled site.
	DeployKey *tlsProv.PrivateKey
	// HostKey is the SSH host key pair of the site's router (its public key is pinned in vars.nix); nil for a
	// disabled site.
	HostKey *tlsProv.PrivateKey
	// NetbirdSetupKey is the NetBird setup key of the site (secret); nil for a disabled site or one without NetBird.
	NetbirdSetupKey *pulumi.StringOutput
	// NutPassword is the password of the NUT user upsmon (secret); nil for a disabled site or one without a UPS.
	NutPassword *pulumi.StringOutput
	// AdguardPassword is the password of the AdGuard Home user admin (secret); nil for a disabled site.
	AdguardPassword *pulumi.StringOutput
	// AdguardPasswordHash is the bcrypt hash of AdguardPassword (secret, what AdGuard Home stores); nil for a disabled
	// site.
	AdguardPasswordHash *pulumi.StringOutput
	// Vars is the content of the vars.nix file of the site.
	Vars pulumi.StringOutput
}

// ConfigureSite creates the resources of a site and renders its vars.nix. An enabled site gets a deploy key, an SSH
// host key, an AdGuard Home password, a NetBird setup key if it runs NetBird and a NUT password if it has a UPS. A disabled site gets none of
// them (disabling a site deletes them); its vars.nix holds only the static SSH keys, so it is still rendered and
// checked, but not deployable.
// ctx: The Pulumi context.
// site: The site configuration.
// staticSSHKeys: The static public SSH keys of the deploy user; the site's generated key is added to them.
// netbirdConfig: The NetBird connection of the core stack.
// netbirdProvider: The NetBird provider.
func ConfigureSite(
	ctx *pulumi.Context,
	site *site.Config,
	staticSSHKeys []string,
	netbirdConfig *netbirdModel.Config,
	netbirdProvider *nbProvider.Provider,
) (*Data, error) {
	if !site.IsEnabled() {
		vars, vErr := renderVars(site, staticSSHKeys, "", netbirdConfig)
		if vErr != nil {
			return nil, vErr
		}

		return &Data{Vars: contextOutput(ctx, vars)}, nil
	}

	name := config.ResourceName(site.Name)

	deployKey, sErr := tls.CreateSSHKey(ctx, name, 0)
	if sErr != nil {
		return nil, sErr
	}

	hostKey, hErr := tls.CreateSSHKey(ctx, config.ResourceName(fmt.Sprintf("%s-host", site.Name)), 0)
	if hErr != nil {
		return nil, hErr
	}

	var setupKey *pulumi.StringOutput
	if site.UsesNetbird() {
		key, kErr := netbird.CreateSetupKey(ctx, netbirdProvider, netbirdConfig, site.Name)
		if kErr != nil {
			return nil, kErr
		}
		setupKey = &key
	}

	var nutPassword *pulumi.StringOutput
	if site.UsesUPS() {
		// The password helper adds no type prefix; the site name is unique within the stack.
		password, pErr := random.CreatePassword(
			ctx,
			fmt.Sprintf("password-nut-%s-%s", site.Name, config.Environment),
			&random.PasswordOptions{
				Length:  passwordLength,
				Special: false,
			},
		)
		if pErr != nil {
			return nil, pErr
		}
		nutPassword = &password.Password
	}

	adguard, aErr := random.CreatePassword(
		ctx,
		fmt.Sprintf("password-adguard-%s-%s", site.Name, config.Environment),
		&random.PasswordOptions{
			Length:  passwordLength,
			Special: false,
		},
	)
	if aErr != nil {
		return nil, aErr
	}

	// An error returned from the apply fails the update instead of writing an empty file.
	vars, _ := pulumi.All(deployKey.PublicKeyOpenssh, hostKey.PublicKeyOpenssh).ApplyT(func(keys []any) (string, error) {
		deployPublicKey, _ := keys[0].(string)
		hostPublicKey, _ := keys[1].(string)
		return renderVars(
			site,
			slices.Concat(staticSSHKeys, []string{strings.TrimSpace(deployPublicKey)}),
			strings.TrimSpace(hostPublicKey),
			netbirdConfig,
		)
	}).(pulumi.StringOutput)

	return &Data{
		DeployKey:           deployKey,
		HostKey:             hostKey,
		NetbirdSetupKey:     setupKey,
		NutPassword:         nutPassword,
		AdguardPassword:     &adguard.Password,
		AdguardPasswordHash: &adguard.Resource.BcryptHash,
		Vars:                vars,
	}, nil
}

// VarsDir returns the directory of a site's vars.nix below the output directory and the bucket path: sites/<site>.
// sites/ is the router fleet's Nix input, copied into the world-readable Nix store as a whole: nothing but the
// vars.nix files may ever be written there.
// name: The site name.
func VarsDir(name string) string {
	return path.Join("sites", name)
}

// KeysDir returns the directory of a site's private files below the output directory and the bucket path:
// keys/<site>, holding the deploy user's private key and, below secrets/, the files pushed to the router.
// name: The site name.
func KeysDir(name string) string {
	return path.Join("keys", name)
}

// contextOutput returns a known value as an output of the program's context. A plain pulumi.String output is not
// awaited when the program ends, so the applies writing it to a file could be cut off.
// ctx: The Pulumi context.
// value: The value of the output.
func contextOutput(ctx *pulumi.Context, value string) pulumi.StringOutput {
	out, resolve, _ := ctx.NewOutput()
	resolve(value)

	str, _ := out.ApplyT(func(v any) string {
		s, _ := v.(string)
		return s
	}).(pulumi.StringOutput)

	return str
}
