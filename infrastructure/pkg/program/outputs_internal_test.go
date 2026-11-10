package program

import (
	"testing"

	tlsProv "github.com/pulumi/pulumi-tls/sdk/v5/go/tls"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	"github.com/stretchr/testify/assert"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/lib/site"
)

// paths returns the files as "<dir>/<name>".
func paths(files []outputFile) []string {
	var out []string
	for _, f := range files {
		out = append(out, f.dir+"/"+f.name)
	}
	return out
}

func TestOutputFilesDisabledSite(t *testing.T) {
	files := outputFiles("a", &site.Data{}, nil)

	assert.Equal(t, []string{"sites/a/vars.nix"}, paths(files))
}

func TestOutputFilesEnabledSite(t *testing.T) {
	secret := pulumi.String("secret").ToStringOutput()
	data := &site.Data{
		DeployKey:           &tlsProv.PrivateKey{},
		HostKey:             &tlsProv.PrivateKey{},
		AdguardPassword:     &secret,
		AdguardPasswordHash: &secret,
	}

	assert.Equal(t, []string{
		"sites/a/vars.nix",
		"keys/a/deploy-key",
		"keys/a/secrets/ssh-host-key",
		"keys/a/adguard-password",
		"keys/a/secrets/adguard-password-hash",
	}, paths(outputFiles("a", data, nil)))
}

func TestOutputFilesOptional(t *testing.T) {
	secret := pulumi.String("secret").ToStringOutput()
	data := &site.Data{NetbirdSetupKey: &secret, NutPassword: &secret}

	assert.Equal(t, []string{
		"sites/a/vars.nix",
		"keys/a/secrets/netbird-setup-key",
		"keys/a/secrets/nut-password",
		"keys/a/secrets/crowdsec-enroll-key",
	}, paths(outputFiles("a", data, pulumi.String("key"))))
}
