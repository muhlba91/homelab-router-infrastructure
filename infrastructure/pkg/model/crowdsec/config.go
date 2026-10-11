package crowdsec

// Config defines the CrowdSec stack configuration (config "crowdsec").
type Config struct {
	// EnrollKey is the enroll key of the CrowdSec console account (secret; one for all sites). Unset or empty: no
	// site enrolls.
	EnrollKey *string `json:"enrollKey,omitempty"`
}
