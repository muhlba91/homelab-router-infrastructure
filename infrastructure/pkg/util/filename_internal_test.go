package util

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/model/config/site"
)

func TestApplyFileName(t *testing.T) {
	cases := map[string]struct {
		site, file string
		order      *int
		wantErr    bool
	}{
		"plain":              {site: "a", file: "a"},
		"order":              {site: "a", file: "010-a", order: new(10)},
		"order zero":         {site: "a", file: "000-a", order: new(0)},
		"digits in name":     {site: "r1", file: "5-r1", order: new(5)},
		"name with dashes":   {site: "a-b", file: "20-a-b", order: new(20)},
		"numeric name":       {site: "123", file: "123"},
		"mismatch":           {site: "b", file: "010-a", wantErr: true},
		"order not stripped": {site: "010-a", file: "010-a", wantErr: true},
		"upper case":         {site: "A", file: "A", wantErr: true},
		"leading dash":       {site: "-a", file: "-a", wantErr: true},
		"empty":              {site: "", file: "", wantErr: true},
		"order too large":    {site: "a", file: "99999999999999999999-a", wantErr: true},
	}

	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			c := &site.Config{Name: tc.site}

			err := applyFileName(c, tc.file)
			if tc.wantErr {
				require.Error(t, err)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tc.order, c.DeployOrder)
		})
	}
}
