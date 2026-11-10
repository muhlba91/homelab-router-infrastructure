package site

import (
	"errors"
	"fmt"
	"path"
	"slices"
	"strings"

	nbProvider "github.com/KitStream/netbird-pulumi-provider/sdk/go/netbird"
	"github.com/muhlba91/pulumi-shared-library/pkg/lib/random"
	"github.com/muhlba91/pulumi-shared-library/pkg/lib/tls"
	randomModel "github.com/muhlba91/pulumi-shared-library/pkg/model/random"
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
// host key, an AdGuard Home password, a NetBird setup key if it runs NetBird and a NUT password if it has a UPS.
// A disabled site gets none of them (disabling a site deletes them); its vars.nix holds only the static SSH keys,
// so it is still rendered and checked, but not deployable.
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
		return configureDisabled(ctx, site, staticSSHKeys, netbirdConfig)
	}

	return configureEnabled(ctx, site, staticSSHKeys, netbirdConfig, netbirdProvider)
}

// configureDisabled renders the vars.nix of a disabled site: no resources.
func configureDisabled(
	ctx *pulumi.Context,
	site *site.Config,
	staticSSHKeys []string,
	netbirdConfig *netbirdModel.Config,
) (*Data, error) {
	vars, err := renderVars(site, staticSSHKeys, "", netbirdConfig)
	if err != nil {
		return nil, err
	}

	out, oErr := contextOutput(ctx, vars)
	if oErr != nil {
		return nil, oErr
	}

	return &Data{Vars: out}, nil
}

// configureEnabled creates the keys and secrets of an enabled site and renders its vars.nix with the public keys.
func configureEnabled(
	ctx *pulumi.Context,
	site *site.Config,
	staticSSHKeys []string,
	netbirdConfig *netbirdModel.Config,
	netbirdProvider *nbProvider.Provider,
) (*Data, error) {
	deployKey, err := tls.CreateSSHKey(ctx, config.ResourceName(site.Name), 0)
	if err != nil {
		return nil, err
	}

	hostKey, err := tls.CreateSSHKey(ctx, config.ResourceName(fmt.Sprintf("%s-host", site.Name)), 0)
	if err != nil {
		return nil, err
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
		nut, nErr := createPassword(ctx, "nut", site.Name)
		if nErr != nil {
			return nil, nErr
		}
		nutPassword = &nut.Password
	}

	adguard, err := createPassword(ctx, "adguard", site.Name)
	if err != nil {
		return nil, err
	}

	vars, err := applyVars(site, staticSSHKeys, netbirdConfig, deployKey, hostKey)
	if err != nil {
		return nil, err
	}

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

// createPassword creates the generated password of a service of a site. The password helper adds no type prefix;
// the site name is unique within the stack.
// ctx: The Pulumi context.
// service: The service the password is for (part of the resource name).
// siteName: The site name.
func createPassword(ctx *pulumi.Context, service, siteName string) (*randomModel.PasswordData, error) {
	return random.CreatePassword(
		ctx,
		fmt.Sprintf("password-%s-%s-%s", service, siteName, config.Environment),
		&random.PasswordOptions{
			Length:  passwordLength,
			Special: false,
		},
	)
}

// applyVars renders the vars.nix of an enabled site once its public keys are known. An error returned from the
// apply fails the update instead of writing an empty file.
func applyVars(
	site *site.Config,
	staticSSHKeys []string,
	netbirdConfig *netbirdModel.Config,
	deployKey, hostKey *tlsProv.PrivateKey,
) (pulumi.StringOutput, error) {
	vars, ok := pulumi.All(deployKey.PublicKeyOpenssh, hostKey.PublicKeyOpenssh).ApplyT(func(keys []any) (string, error) {
		deployPublicKey, dOk := keys[0].(string)
		hostPublicKey, hOk := keys[1].(string)
		if !dOk || !hOk {
			return "", errors.New("the public SSH keys of the site are not strings")
		}

		return renderVars(
			site,
			slices.Concat(staticSSHKeys, []string{strings.TrimSpace(deployPublicKey)}),
			strings.TrimSpace(hostPublicKey),
			netbirdConfig,
		)
	}).(pulumi.StringOutput)
	if !ok {
		return pulumi.StringOutput{}, errors.New("the vars.nix of the site is not a string output")
	}

	return vars, nil
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
func contextOutput(ctx *pulumi.Context, value string) (pulumi.StringOutput, error) {
	out, resolve, _ := ctx.NewOutput()
	resolve(value)

	str, ok := out.ApplyT(func(v any) (string, error) {
		s, sOk := v.(string)
		if !sOk {
			return "", errors.New("the output of the context is not a string")
		}
		return s, nil
	}).(pulumi.StringOutput)
	if !ok {
		return pulumi.StringOutput{}, errors.New("the context output is not a string output")
	}

	return str, nil
}
