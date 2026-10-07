package util

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/rs/zerolog/log"
	"gopkg.in/yaml.v3"

	"github.com/muhlba91/homelab-router-infrastructure/pkg/model/config/site"
)

// fileName matches a site file's name without its extension: an optional deploy order (digits and a dash), then
// the site name.
var fileName = regexp.MustCompile(`^(?:([0-9]+)-)?(.+)$`)

// siteName matches a valid site name: a hostname label.
var siteName = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$`)

// ParseSitesFromFiles reads the site configuration files (*.yml, *.yaml) from the specified directory.
// Other entries (e.g. .gitkeep) are skipped. A file must be named after its site, optionally prefixed with its deploy
// order ([<order>-]<name>.yml), and every site name must be unique.
// dir: The directory of the site configuration files.
func ParseSitesFromFiles(dir string) ([]*site.Config, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		log.Err(err).Msgf("[site] error reading site configuration directory: %s", dir)
		return nil, err
	}

	var sites []*site.Config
	seen := make(map[string]string)
	for _, e := range entries {
		ext := filepath.Ext(e.Name())
		if !e.Type().IsRegular() || (ext != ".yml" && ext != ".yaml") {
			continue
		}

		full := filepath.Join(dir, e.Name())
		r, lErr := loadSiteFile(full, strings.TrimSuffix(e.Name(), ext))
		if lErr != nil {
			return nil, lErr
		}
		if other, ok := seen[r.Name]; ok {
			dErr := fmt.Errorf("site %q is defined twice: %s and %s", r.Name, other, full)
			log.Err(dErr).Msgf("[site] error validating site configuration file: %s", full)
			return nil, dErr
		}
		seen[r.Name] = full
		sites = append(sites, r)
	}

	return sites, nil
}

// loadSiteFile reads one site file and applies its name: the site name must match it, and its prefix (if any) is
// the site's deploy order.
// path: The path of the file.
// name: The file name without its extension ([<order>-]<name>).
func loadSiteFile(path string, name string) (*site.Config, error) {
	r, err := parseSiteFile(path)
	if err != nil {
		return nil, err
	}

	if nErr := applyFileName(r, name); nErr != nil {
		log.Err(nErr).Msgf("[site] error validating site configuration file: %s", path)
		return nil, nErr
	}

	return r, nil
}

// applyFileName checks the file name of a site against its name and sets the deploy order from its prefix.
// r: The site configuration.
// name: The file name without its extension ([<order>-]<name>).
func applyFileName(r *site.Config, name string) error {
	parts := fileName.FindStringSubmatch(name)
	if parts == nil || !siteName.MatchString(parts[2]) {
		return fmt.Errorf("file name %q: the site name must be a hostname label", name)
	}
	if r.Name != parts[2] {
		return fmt.Errorf("site name %q does not match the file name %q", r.Name, name)
	}
	if parts[1] == "" {
		return nil
	}

	order, err := strconv.Atoi(parts[1])
	if err != nil {
		return fmt.Errorf("deploy order of %q: %w", name, err)
	}
	r.DeployOrder = &order

	return nil
}

// parseSiteFile decodes one site configuration file. Unknown keys are errors, so a typo cannot silently
// leave a value at its default.
// path: The path of the file.
func parseSiteFile(path string) (*site.Config, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Err(err).Msgf("[site] error reading site configuration file: %s", path)
		return nil, err
	}

	var r site.Config
	dec := yaml.NewDecoder(bytes.NewReader(b))
	dec.KnownFields(true)
	if yErr := dec.Decode(&r); yErr != nil {
		log.Err(yErr).Msgf("[site] error parsing site configuration file: %s", path)
		return nil, fmt.Errorf("%s: %w", path, yErr)
	}
	if !errors.Is(dec.Decode(new(any)), io.EOF) {
		return nil, fmt.Errorf("%s: more than one YAML document", path)
	}
	if lErr := checkLists(&r); lErr != nil {
		return nil, fmt.Errorf("%s: %w", path, lErr)
	}

	return &r, nil
}

// checkLists rejects empty lists: the template renders them like omitted ones (`from: []` would open a forward to
// everyone).
// r: The site configuration.
func checkLists(r *site.Config) error {
	if r.Firewall == nil {
		return nil
	}
	if r.Firewall.Forwards != nil {
		for _, f := range slices.Concat(r.Firewall.Forwards.V4, r.Firewall.Forwards.V6) {
			if f.From != nil && len(f.From) == 0 {
				return fmt.Errorf("forward to %s: from must not be empty (omit it for everyone)", f.To)
			}
		}
	}
	for _, name := range slices.Sorted(maps.Keys(r.Firewall.Services)) {
		s := r.Firewall.Services[name]
		if s != nil && ((s.Ports != nil && len(s.Ports) == 0) || (s.From != nil && len(s.From) == 0)) {
			return fmt.Errorf(
				"service %s: ports and from must not be empty (omit them for the defaults, close it with enabled: false)",
				name,
			)
		}
	}
	return nil
}
