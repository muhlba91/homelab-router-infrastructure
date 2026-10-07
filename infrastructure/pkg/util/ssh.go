package util

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/rs/zerolog/log"
	"golang.org/x/crypto/ssh"
)

// ParseSSHKeysFromFiles reads the public SSH keys from the *.pub files in the specified directory, in file name
// order. Every non-empty line that is not a comment (#) is one key in authorized_keys format; each key is validated
// and returned as written (comment included). At least one key is required: without one, deploys are locked out.
// dir: The directory of the public key files.
func ParseSSHKeysFromFiles(dir string) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		log.Err(err).Msgf("[ssh] error reading ssh key directory: %s", dir)
		return nil, err
	}

	var keys []string
	for _, e := range entries {
		if !e.Type().IsRegular() || filepath.Ext(e.Name()) != ".pub" {
			continue
		}

		full := filepath.Join(dir, e.Name())
		b, rErr := os.ReadFile(full)
		if rErr != nil {
			log.Err(rErr).Msgf("[ssh] error reading ssh key file: %s", full)
			return nil, rErr
		}

		for i, line := range strings.Split(string(b), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			if _, _, _, _, pErr := ssh.ParseAuthorizedKey([]byte(line)); pErr != nil {
				kErr := fmt.Errorf("%s:%d: invalid public key: %w", full, i+1, pErr)
				log.Err(kErr).Msg("[ssh] error parsing ssh key file")
				return nil, kErr
			}
			keys = append(keys, line)
		}
	}

	if len(keys) == 0 {
		nErr := errors.New("no public keys found in " + dir + " (*.pub)")
		log.Err(nErr).Msg("[ssh] error reading ssh keys")
		return nil, nErr
	}

	return keys, nil
}
