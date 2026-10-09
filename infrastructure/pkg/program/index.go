package program

import (
	"os"
	"path"
	"path/filepath"

	"github.com/muhlba91/pulumi-shared-library/pkg/util/dir"
	"github.com/muhlba91/pulumi-shared-library/pkg/util/storage"
	scwUpload "github.com/muhlba91/pulumi-shared-library/pkg/util/storage/scaleway"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/lib/config"
	"github.com/muhlba91/homelab-router-infrastructure/pkg/lib/netbird"
	"github.com/muhlba91/homelab-router-infrastructure/pkg/lib/site"
)

// outputDir is the local directory the files are written to (the router fleet's OUTPUTS).
const outputDir = "outputs"

// secretPermissions are the permissions of the written files.
const secretPermissions os.FileMode = 0o600

// outputDirPermissions are the permissions of the output directories, which hold private keys.
const outputDirPermissions os.FileMode = 0o700

// Run is the Pulumi program: it creates the resources of every site and writes its files.
// ctx: The Pulumi context.
func Run(ctx *pulumi.Context) error {
	sites, sshKeys, netbirdConfig, err := config.LoadConfig(ctx)
	if err != nil {
		return err
	}

	if dErr := dir.Create(outputDir); dErr != nil {
		return dErr
	}

	netbirdProvider, pErr := netbird.CreateProvider(ctx, netbirdConfig)
	if pErr != nil {
		return pErr
	}

	outputs := pulumi.Map{}
	for _, data := range sites {
		siteData, sErr := site.ConfigureSite(ctx, data, sshKeys, netbirdConfig, netbirdProvider)
		if sErr != nil {
			return sErr
		}

		if wErr := writeOutputFiles(ctx, data.Name, siteData); wErr != nil {
			return wErr
		}

		outputs[data.Name] = siteOutput(siteData)
	}

	ctx.Export("sites", outputs)

	return nil
}

// siteOutput returns a site's part of the stack output "sites": {passwords: {adguard, nut}}. The nut password is
// only there for a site with a UPS; a disabled site has none.
// siteData: The generated resources and files of the site.
func siteOutput(siteData *site.Data) pulumi.Map {
	passwords := pulumi.Map{}
	if siteData.AdguardPassword != nil {
		passwords["adguard"] = *siteData.AdguardPassword
	}
	if siteData.NutPassword != nil {
		passwords["nut"] = *siteData.NutPassword
	}

	return pulumi.Map{"passwords": passwords}
}

// writeOutputFiles writes the files of a site below outputs/ (the layout the router fleet's ./router reads) and
// uploads them to the bucket under the same paths: sites/<site>/vars.nix and, for an enabled site,
// keys/<site>/deploy-key (the deploy user's private key), keys/<site>/adguard-password (for logging in) and
// keys/<site>/secrets/ (pushed to the router: the SSH host key, the AdGuard password hash, the NetBird setup key, the
// NUT password).
// ctx: The Pulumi context.
// name: The name of the site.
// siteData: The generated resources and files of the site.
func writeOutputFiles(ctx *pulumi.Context, name string, siteData *site.Data) error {
	type outputFile struct {
		dir     string
		name    string
		content pulumi.StringInput
	}

	keysDir := site.KeysDir(name)
	secretsDir := path.Join(keysDir, "secrets")

	files := []outputFile{{site.VarsDir(name), "vars.nix", siteData.Vars}}
	if siteData.DeployKey != nil {
		files = append(files, outputFile{keysDir, "deploy-key", siteData.DeployKey.PrivateKeyOpenssh})
	}
	if siteData.HostKey != nil {
		files = append(files, outputFile{secretsDir, "ssh-host-key", siteData.HostKey.PrivateKeyOpenssh})
	}
	if siteData.NetbirdSetupKey != nil {
		files = append(files, outputFile{secretsDir, "netbird-setup-key", *siteData.NetbirdSetupKey})
	}
	if siteData.NutPassword != nil {
		files = append(files, outputFile{secretsDir, "nut-password", *siteData.NutPassword})
	}
	if siteData.AdguardPassword != nil {
		files = append(files, outputFile{keysDir, "adguard-password", *siteData.AdguardPassword})
		files = append(files, outputFile{secretsDir, "adguard-password-hash", *siteData.AdguardPasswordHash})
	}

	for _, file := range files {
		// The files are written asynchronously, and a failed write is only logged: create the directory first.
		outputPath := filepath.Join(".", outputDir, filepath.FromSlash(file.dir))
		if err := os.MkdirAll(outputPath, outputDirPermissions); err != nil {
			return err
		}

		scwUpload.WriteFileAndUpload(ctx, &storage.WriteFileAndUploadOptions{
			BucketID:    config.BucketID,
			BucketPath:  path.Join(config.BucketPath, file.dir),
			OutputPath:  outputPath,
			Name:        file.name,
			Content:     file.content,
			Labels:      config.CommonLabels(),
			Permissions: []os.FileMode{secretPermissions},
		})
	}

	return nil
}
