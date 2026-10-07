// Package mocks provides Pulumi mocks for the program's tests: fake values for the generated resources and the core
// stack's NetBird output, so the program runs offline.
package mocks

import (
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

// PublicKey is the public key every mocked SSH key returns (a throw-away key; its private half does not exist).
const PublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri mock"

// Mocks returns fake outputs for the resources of the program.
type Mocks struct{}

// NewResource returns the inputs of a resource plus fake values for its generated outputs.
// args: The resource's type, name and inputs.
func (Mocks) NewResource(args pulumi.MockResourceArgs) (string, resource.PropertyMap, error) {
	outputs := args.Inputs.Copy()

	switch args.TypeToken {
	case "pulumi:pulumi:StackReference":
		outputs = resource.PropertyMap{"outputs": resource.NewObjectProperty(resource.PropertyMap{
			"netbird": resource.MakeSecret(resource.NewObjectProperty(resource.NewPropertyMapFromMap(map[string]any{
				"address":       "https://netbird.example.org:443",
				"pat":           "mock-pat",
				"client":        map[string]any{"ipv4": "10.253.0.1"},
				"backboneGroup": "mock-group",
			}))),
		})}
	case "tls:index/privateKey:PrivateKey":
		outputs["publicKeyOpenssh"] = resource.NewStringProperty(PublicKey + "\n")
		outputs["privateKeyOpenssh"] = resource.MakeSecret(resource.NewStringProperty("mock-private-key-" + args.Name))
	case "random:index/randomPassword:RandomPassword":
		outputs["result"] = resource.MakeSecret(resource.NewStringProperty("mock-password-" + args.Name))
		outputs["bcryptHash"] = resource.MakeSecret(resource.NewStringProperty("$2a$10$mock-hash-" + args.Name))
	case "netbird:index/setupKey:SetupKey":
		outputs["key"] = resource.MakeSecret(resource.NewStringProperty("mock-setup-key-" + args.Name))
	}

	return args.Name + "-id", outputs, nil
}

// Call returns the arguments of a function call unchanged.
// args: The function's token and arguments.
func (Mocks) Call(args pulumi.MockCallArgs) (resource.PropertyMap, error) {
	return args.Args, nil
}
