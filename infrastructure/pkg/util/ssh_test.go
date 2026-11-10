package util_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/util"
)

const (
	keyA = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri a@example"
	keyB = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFhl/9WAbovwuyCeVz+1yll3s5SVzWSnukMPnLs7a1ri b@example"
)

func writeKeys(t *testing.T, files map[string]string) string {
	t.Helper()

	dir := t.TempDir()
	for name, content := range files {
		require.NoError(t, os.WriteFile(filepath.Join(dir, name), []byte(content), 0o600))
	}
	return dir
}

func TestParseSSHKeysSkipsCommentsAndBlankLines(t *testing.T) {
	keys, err := util.ParseSSHKeysFromFiles(writeKeys(t, map[string]string{
		"b.pub":     "\n" + keyB + "\n",
		"a.pub":     "# the first key\n\n  " + keyA + "  \n",
		"other.txt": "not a key",
	}))

	require.NoError(t, err)
	assert.Equal(t, []string{keyA, keyB}, keys, "file name order, trimmed, comment kept")
}

func TestParseSSHKeysInvalidKey(t *testing.T) {
	_, err := util.ParseSSHKeysFromFiles(writeKeys(t, map[string]string{"a.pub": keyA + "\nnot-a-key\n"}))

	require.Error(t, err)
	assert.Contains(t, err.Error(), "a.pub:2")
}

func TestParseSSHKeysNoFiles(t *testing.T) {
	for name, files := range map[string]map[string]string{
		"empty directory": {},
		"only comments":   {"a.pub": "# nothing\n\n"},
		"no .pub file":    {"a.txt": keyA},
	} {
		_, err := util.ParseSSHKeysFromFiles(writeKeys(t, files))
		require.Error(t, err, name)
	}

	_, err := util.ParseSSHKeysFromFiles(filepath.Join(t.TempDir(), "missing"))
	require.Error(t, err)
}
