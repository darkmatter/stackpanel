// Package setupsession holds short-lived browser readiness evidence outside the
// generated repository. Coding-agent output cannot create a successful session.
package setupsession

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/userconfig"
)

const DefaultStudioURL = "https://local.stackpanel.com/studio"

type Session struct {
	ID             string    `json:"id"`
	Root           string    `json:"root"`
	ProjectID      string    `json:"projectId"`
	AgentID        string    `json:"agentId"`
	Endpoint       string    `json:"endpoint"`
	Origin         string    `json:"origin"`
	Expires        time.Time `json:"expires"`
	Services       []string  `json:"services,omitempty"`
	RequireBrowser bool      `json:"requireBrowser"`
	Connection     string    `json:"connection,omitempty"`
	ConnectedAt    time.Time `json:"connectedAt"`
	ReadyAt        time.Time `json:"readyAt"`
	ConfigLoadedAt time.Time `json:"configLoadedAt"`
}

var updateMu sync.Mutex

func Directory() string {
	return filepath.Join(filepath.Dir(userconfig.GetConfigPath()), "setup-sessions")
}
func sessionPath(id string) (string, error) {
	b, err := hex.DecodeString(id)
	if err != nil || len(b) != 32 {
		return "", fmt.Errorf("invalid setup session ID")
	}
	return filepath.Join(Directory(), id+".json"), nil
}
func Create(s Session) (Session, error) {
	var nonce [32]byte
	if _, err := rand.Read(nonce[:]); err != nil {
		return s, err
	}
	s.ID = hex.EncodeToString(nonce[:])
	s.Expires = time.Now().Add(15 * time.Minute)
	s.Connection = ""
	s.ReadyAt = time.Time{}
	s.ConfigLoadedAt = time.Time{}
	s.ConnectedAt = time.Time{}
	root, err := filepath.EvalSymlinks(s.Root)
	if err != nil {
		return s, err
	}
	s.Root = root
	return s, save(s)
}
func Load(id string) (Session, error) {
	var s Session
	path, err := sessionPath(id)
	if err != nil {
		return s, err
	}
	f, err := os.Open(path)
	if err != nil {
		return s, err
	}
	defer f.Close()
	if err := json.NewDecoder(io.LimitReader(f, 65536)).Decode(&s); err != nil {
		return s, err
	}
	if s.ID != id || !time.Now().Before(s.Expires) {
		return s, fmt.Errorf("setup session expired or invalid; rerun setup")
	}
	return s, nil
}
func save(s Session) error {
	path, err := sessionPath(s.ID)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(Directory(), 0o700); err != nil {
		return err
	}
	f, err := os.CreateTemp(Directory(), ".session-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	err = json.NewEncoder(f).Encode(s)
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(f.Name(), path)
}

// Update serializes server writes; readers see complete snapshots via rename.
func Update(id string, fn func(*Session) error) error {
	updateMu.Lock()
	defer updateMu.Unlock()
	s, err := Load(id)
	if err != nil {
		return err
	}
	if err := fn(&s); err != nil {
		return err
	}
	return save(s)
}
func ValidateBrowser(s Session, agentID, origin, projectID string) error {
	if s.AgentID != agentID || s.Origin != origin || s.ProjectID != projectID {
		return fmt.Errorf("setup session does not match this agent, browser origin, and project")
	}
	return nil
}
func RecordReady(id, agentID, origin, projectID string) error {
	return Update(id, func(s *Session) error {
		if err := ValidateBrowser(*s, agentID, origin, projectID); err != nil {
			return err
		}
		if s.Connection == "" || time.Since(s.ConnectedAt) > 15*time.Second || s.ConfigLoadedAt.IsZero() || time.Since(s.ConfigLoadedAt) > time.Minute {
			return fmt.Errorf("waiting for a live event connection")
		}
		s.ReadyAt = time.Now()
		return nil
	})
}

type Health struct {
	ProjectRoot   string `json:"project_root"`
	DevshellReady bool   `json:"devshell_ready"`
	Status        string `json:"status"`
	AgentID       string `json:"agent_id"`
	SetupVersion  int    `json:"setup_version"`
}

func ReadHealth(ctxClient *http.Client, endpoint string) (Health, error) {
	var health Health
	resp, err := ctxClient.Get(endpoint + "/health")
	if err != nil {
		return health, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return health, fmt.Errorf("agent health returned %s", resp.Status)
	}
	err = json.NewDecoder(io.LimitReader(resp.Body, 65536)).Decode(&health)
	if err == nil && (health.Status != "ok" || health.AgentID == "") {
		err = fmt.Errorf("endpoint did not return Stackpanel agent health")
	}
	return health, err
}

func StudioURL(base string, s Session) (string, error) {
	if base == "" {
		base = DefaultStudioURL
	}
	u, err := url.Parse(base)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil {
		return "", fmt.Errorf("invalid Studio URL")
	}
	if u.Path == "" || u.Path == "/" {
		u.Path = "/studio"
	}
	q := u.Query()
	if s.ID == "" {
		q.Del("setup")
	} else {
		q.Set("setup", s.ID)
	}
	q.Set("project", s.ProjectID)
	q.Set("agent", s.Endpoint)
	q.Del("demo")
	u.RawQuery = q.Encode()
	return u.String(), nil
}
