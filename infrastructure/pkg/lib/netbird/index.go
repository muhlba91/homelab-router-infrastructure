package netbird

import (
	nbProvider "github.com/KitStream/netbird-pulumi-provider/sdk/go/netbird"
	"github.com/muhlba91/pulumi-shared-library/pkg/lib/netbird/setupkey"
	"github.com/muhlba91/pulumi-shared-library/pkg/model/rotation"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/lib/config"
	netbirdModel "github.com/muhlba91/homelab-router-infrastructure/pkg/model/netbird"
)

// setupKeyRotationDays is the rotation period of the setup keys. A key is only used to enroll a router, so a
// rotation does not affect an enrolled one.
const setupKeyRotationDays = 180

// CreateProvider creates the NetBird provider to manage resources of the NetBird instance via its API.
// ctx: The Pulumi context.
// netbirdConfig: The NetBird connection of the core stack.
func CreateProvider(ctx *pulumi.Context, netbirdConfig *netbirdModel.Config) (*nbProvider.Provider, error) {
	return nbProvider.NewProvider(ctx, "netbird", &nbProvider.ProviderArgs{
		ManagementUrl: pulumi.String(netbirdConfig.Address),
		Token:         pulumi.String(netbirdConfig.PAT), // stored as a secret by the provider
	})
}

// CreateSetupKey creates a reusable, non-ephemeral NetBird setup key for the given site that puts the router into
// the backbone group. The key is a secret output (marked by the provider).
// ctx: The Pulumi context.
// provider: The NetBird provider.
// netbirdConfig: The NetBird connection of the core stack.
// site: The site name for which the setup key is created.
func CreateSetupKey(
	ctx *pulumi.Context,
	provider *nbProvider.Provider,
	netbirdConfig *netbirdModel.Config,
	site string,
) (pulumi.StringOutput, error) {
	name := config.ResourceName(site)

	key, err := setupkey.Create(ctx, name, &setupkey.CreateOptions{
		Type: pulumi.String("reusable"),
		// The rotation is named after the key (rotation-netbird-setup-key-<name>).
		Rotation: &rotation.Options{
			Days: setupKeyRotationDays,
		},
		AutoGroups: pulumi.StringArray{
			pulumi.String(netbirdConfig.BackboneGroup),
		},
		PulumiOptions: []pulumi.ResourceOption{pulumi.Provider(provider)},
	})
	if err != nil {
		return pulumi.StringOutput{}, err
	}

	return key.Key, nil
}
