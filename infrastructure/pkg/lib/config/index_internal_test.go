package config

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/model/config/site"
	crowdsecModel "github.com/muhlba91/homelab-router-infrastructure/pkg/model/crowdsec"
)

func TestParseNetbirdConfig(t *testing.T) {
	cfg, err := parseNetbirdConfig(map[string]any{
		"address":       "https://netbird.example.org:443",
		"pat":           "token",
		"client":        map[string]any{"ipv4": "10.253.0.1"},
		"backboneGroup": "group",
	})

	require.NoError(t, err)
	assert.Equal(t, "https://netbird.example.org:443", cfg.Address)
	assert.Equal(t, "token", cfg.PAT)
	assert.Equal(t, "10.253.0.1", cfg.HubIP)
	assert.Equal(t, "group", cfg.BackboneGroup)
}

func TestParseNetbirdConfigInvalid(t *testing.T) {
	_, err := parseNetbirdConfig(nil)
	require.Error(t, err)
	_, err = parseNetbirdConfig("netbird")
	require.Error(t, err)

	_, err = parseNetbirdConfig(map[string]any{"address": "a", "client": "not a map", "backboneGroup": 1})
	require.Error(t, err)
	for _, field := range []string{"netbird.pat", "netbird.client.ipv4", "netbird.backboneGroup"} {
		assert.Contains(t, err.Error(), field, "every missing value is reported")
	}
	assert.NotContains(t, err.Error(), "netbird.address")
}

func TestResourceName(t *testing.T) {
	Environment = "prod"
	assert.Equal(t, "router-infrastructure-site-a-prod", ResourceName("site-a"))
}

func consoleSite(name string, console *bool) *site.Config {
	return &site.Config{
		Name: name,
		Security: &site.SecurityConfig{CrowdSec: &site.CrowdSecConfig{
			Console: &site.CrowdSecConsoleConfig{Enabled: console},
		}},
	}
}

func TestDropCrowdSecConsole(t *testing.T) {
	yes, no := true, false
	build := func() []*site.Config {
		return []*site.Config{consoleSite("on", &yes), consoleSite("off", &no), {Name: "none"}}
	}

	t.Run("without enroll key", func(t *testing.T) {
		for _, key := range []*string{nil, new("")} {
			sites := build()
			dropCrowdSecConsole(sites, &crowdsecModel.Config{EnrollKey: key})

			assert.False(t, sites[0].UsesCrowdSecConsole())
			assert.False(t, sites[1].UsesCrowdSecConsole())
			assert.Nil(t, sites[2].Security)
		}
	})

	t.Run("with enroll key", func(t *testing.T) {
		sites := build()
		dropCrowdSecConsole(sites, &crowdsecModel.Config{EnrollKey: new("key")})

		assert.True(t, sites[0].UsesCrowdSecConsole())
		assert.False(t, sites[1].UsesCrowdSecConsole())
	})
}
