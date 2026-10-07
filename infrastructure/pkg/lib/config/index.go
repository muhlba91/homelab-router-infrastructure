package config

import (
	"errors"
	"fmt"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
	"github.com/rs/zerolog/log"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/model/config/site"
	netbirdModel "github.com/muhlba91/homelab-router-infrastructure/pkg/model/netbird"
	"github.com/muhlba91/homelab-router-infrastructure/pkg/util"
)

const (
	// coreProject is the Pulumi project of the core infrastructure (the hub).
	coreProject = "muehlbachler-core-infrastructure"
	// sitesDir is the directory of the site configuration files.
	sitesDir = "./assets/sites"
	// sshKeysDir is the directory of the static public SSH keys of the deploy user.
	sshKeysDir = "./assets/ssh"
)

//nolint:gochecknoglobals // global configuration is acceptable here
var (
	// Environment is the stack name (e.g. prod); it selects the core stack of the same name.
	Environment string
	// GlobalName is the prefix of the resource names and the bucket path.
	GlobalName = "router-infrastructure"
	// BucketPath is the path within the buckets for this project.
	BucketPath string
	// BucketID is the ID of the main storage bucket.
	BucketID string
)

// LoadConfig loads the configuration for the given Pulumi context: the site configurations, the static public SSH
// keys of the deploy user (the same for every site) and the NetBird connection of the core stack.
// ctx: The Pulumi context.
func LoadConfig(
	ctx *pulumi.Context,
) ([]*site.Config, []string, *netbirdModel.Config, error) {
	Environment = ctx.Stack()

	cfg := config.New(ctx, "")

	BucketID = cfg.Require("bucketId")
	BucketPath = fmt.Sprintf("%s/%s", GlobalName, Environment)

	netbirdConfig, nErr := loadNetbirdConfig(ctx)
	if nErr != nil {
		log.Err(nErr).Msg("[config] error loading the netbird configuration from the core infrastructure stack")
		return nil, nil, nil, nErr
	}

	sites, rErr := util.ParseSitesFromFiles(sitesDir)
	if rErr != nil {
		log.Err(rErr).Msg("[config] error parsing site configurations from files")
		return nil, nil, nil, rErr
	}

	sshKeys, kErr := util.ParseSSHKeysFromFiles(sshKeysDir)
	if kErr != nil {
		log.Err(kErr).Msg("[config] error parsing ssh keys from files")
		return nil, nil, nil, kErr
	}

	return sites, sshKeys, netbirdConfig, nil
}

// ResourceName returns the name of a site's resources: <global name>-<site>-<environment>. The resource helpers of
// the shared library prefix it with their type (e.g. ssh-key-, netbird-setup-key-).
// site: The site name.
func ResourceName(site string) string {
	return fmt.Sprintf("%s-%s-%s", GlobalName, site, Environment)
}

// CommonLabels returns a map of common labels to be used across resources.
func CommonLabels() map[string]string {
	return map[string]string{
		"environment": Environment,
	}
}

// loadNetbirdConfig reads the output "netbird" of the core infrastructure stack of the same environment.
// The values are awaited here, so every resource that depends on them is created at the top level (and is
// therefore part of a preview). Every value is required: a setup key without the backbone group enrolls a
// router that cannot reach the hub.
// ctx: The Pulumi context.
func loadNetbirdConfig(ctx *pulumi.Context) (*netbirdModel.Config, error) {
	coreStack, sErr := pulumi.NewStackReference(
		ctx,
		fmt.Sprintf("%s/%s/%s", ctx.Organization(), coreProject, Environment),
		nil,
	)
	if sErr != nil {
		return nil, sErr
	}

	details, dErr := coreStack.GetOutputDetails("netbird")
	if dErr != nil {
		return nil, dErr
	}
	// The output holds the token, so it is usually a secret as a whole.
	raw := details.Value
	if raw == nil {
		raw = details.SecretValue
	}
	nbData, ok := raw.(map[string]any)
	if !ok {
		return nil, errors.New("output netbird of the core stack is missing")
	}
	nbClient, _ := nbData["client"].(map[string]any)

	nbConfig := &netbirdModel.Config{
		Address:       stringValue(nbData, "address"),
		PAT:           stringValue(nbData, "pat"),
		HubIP:         stringValue(nbClient, "ipv4"),
		BackboneGroup: stringValue(nbData, "backboneGroup"),
	}

	var missing []error
	for _, field := range []struct{ key, value string }{
		{"netbird.address", nbConfig.Address},
		{"netbird.pat", nbConfig.PAT},
		{"netbird.client.ipv4", nbConfig.HubIP},
		{"netbird.backboneGroup", nbConfig.BackboneGroup},
	} {
		if field.value == "" {
			missing = append(missing, fmt.Errorf("output %s of the core stack is missing or empty", field.key))
		}
	}
	if len(missing) > 0 {
		return nil, errors.Join(missing...)
	}

	return nbConfig, nil
}

// stringValue returns the string at key of a stack output map, or "" if it is missing or not a string.
// data: The stack output map (may be nil).
// key: The key to read.
func stringValue(data map[string]any, key string) string {
	s, _ := data[key].(string)
	return s
}
