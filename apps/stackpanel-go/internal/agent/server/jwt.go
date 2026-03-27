package server

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/rs/zerolog/log"
)

const (
	TokenExpiration = 30 * 24 * time.Hour // 30 days
	TokenIssuer     = "stackpanel-agent"
)

// AgentClaims extends standard JWT claims with agent-specific fields.
type AgentClaims struct {
	jwt.RegisteredClaims

	// AgentID binds this token to a specific agent instance. Tokens from
	// previous agent sessions are rejected, forcing re-pairing on restart.
	AgentID string `json:"agent_id"`

	// Origin restricts which browser origin can use this token (CORS enforcement).
	Origin string `json:"origin,omitempty"`
}

// JWTManager handles JWT token generation and validation.
//
// In normal mode, signing keys and agent IDs are randomly generated on each startup,
// which means all tokens from previous sessions are automatically invalidated.
// In test mode, keys are derived deterministically from a shared secret so that
// tokens survive agent restarts (useful for E2E tests and CI).
type JWTManager struct {
	signingKey []byte
	agentID    string // Changes per restart in normal mode, stable in test mode
	testMode   bool
}

// JWTManagerOptions configures the JWT manager.
type JWTManagerOptions struct {
	// TestPairingToken, when set, enables test mode: the signing key and agent ID
	// are derived from this secret via SHA-256, making tokens deterministic and
	// valid across agent restarts. Leave empty for production use.
	TestPairingToken string
}

// NewJWTManager creates a new JWT manager with a random signing key and agent ID
func NewJWTManager() (*JWTManager, error) {
	return NewJWTManagerWithOptions(JWTManagerOptions{})
}

// NewJWTManagerWithOptions creates a JWT manager with the given options.
// If TestPairingToken is set, uses deterministic keys for testing.
func NewJWTManagerWithOptions(opts JWTManagerOptions) (*JWTManager, error) {
	var signingKey []byte
	var agentID string
	var testMode bool

	if opts.TestPairingToken != "" {
		// Test mode: derive deterministic signing key and agent ID from the secret
		testMode = true

		// Derive signing key: SHA256(secret + "signing-key")
		h := sha256.New()
		h.Write([]byte(opts.TestPairingToken))
		h.Write([]byte(":signing-key"))
		signingKey = h.Sum(nil)

		// Derive agent ID: SHA256(secret + "agent-id"), take first 16 bytes
		h = sha256.New()
		h.Write([]byte(opts.TestPairingToken))
		h.Write([]byte(":agent-id"))
		agentIDBytes := h.Sum(nil)[:16]
		agentID = base64.RawURLEncoding.EncodeToString(agentIDBytes)

		log.Warn().
			Str("agent_id", agentID).
			Msg("JWT manager initialized in TEST MODE with deterministic keys - do not use in production")
	} else {
		// Normal mode: generate random signing key and agent ID
		testMode = false

		// Generate a random 32-byte signing key
		signingKey = make([]byte, 32)
		if _, err := rand.Read(signingKey); err != nil {
			return nil, fmt.Errorf("failed to generate signing key: %w", err)
		}

		// Generate a random agent ID (16 bytes = 22 base64 chars)
		agentIDBytes := make([]byte, 16)
		if _, err := rand.Read(agentIDBytes); err != nil {
			return nil, fmt.Errorf("failed to generate agent ID: %w", err)
		}
		agentID = base64.RawURLEncoding.EncodeToString(agentIDBytes)
	}

	return &JWTManager{
		signingKey: signingKey,
		agentID:    agentID,
		testMode:   testMode,
	}, nil
}

// IsTestMode returns true if the manager is using deterministic keys for testing
func (m *JWTManager) IsTestMode() bool {
	return m.testMode
}

// GenerateTestToken generates a token for testing with a very long expiration (10 years).
// This is only available in test mode and is intended for E2E tests and CI pipelines.
// The token is deterministic based on the TestPairingToken secret.
func (m *JWTManager) GenerateTestToken(origin string) (string, error) {
	if !m.testMode {
		return "", fmt.Errorf("GenerateTestToken is only available in test mode")
	}

	// Use a fixed "issued at" time for deterministic tokens
	// We use Unix epoch + 1 day to avoid any edge cases with zero time
	fixedTime := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)

	claims := AgentClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    TokenIssuer,
			Subject:   "pair",
			IssuedAt:  jwt.NewNumericDate(fixedTime),
			ExpiresAt: jwt.NewNumericDate(fixedTime.Add(10 * 365 * 24 * time.Hour)), // 10 years
			ID:        "test-token-id",                                              // Fixed JTI for deterministic output
		},
		AgentID: m.agentID,
		Origin:  origin,
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(m.signingKey)
}

// GenerateTestTokenStatic generates a deterministic test token without needing
// a JWTManager instance. Returns (token, agentID, error). Used by the CLI's
// `agent test-token` command so E2E tests can obtain a valid token.
func GenerateTestTokenStatic(testPairingSecret, origin string) (string, string, error) {
	mgr, err := NewJWTManagerWithOptions(JWTManagerOptions{
		TestPairingToken: testPairingSecret,
	})
	if err != nil {
		return "", "", err
	}

	token, err := mgr.GenerateTestToken(origin)
	if err != nil {
		return "", "", err
	}

	return token, mgr.GetAgentID(), nil
}

// GenerateToken creates a new JWT token for the given origin
func (m *JWTManager) GenerateToken(origin string) (string, error) {
	now := time.Now()

	claims := AgentClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    TokenIssuer,
			Subject:   "pair",
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(TokenExpiration)),
			ID:        generateJTI(),
		},
		AgentID: m.agentID,
		Origin:  origin,
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(m.signingKey)
}

// ValidateToken validates a JWT token and returns the claims if valid.
// Rejects tokens from different agent instances (stale tokens after restart).
func (m *JWTManager) ValidateToken(tokenString string) (*AgentClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &AgentClaims{}, func(token *jwt.Token) (interface{}, error) {
		// Verify signing method
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return m.signingKey, nil
	})

	if err != nil {
		return nil, fmt.Errorf("invalid token: %w", err)
	}

	claims, ok := token.Claims.(*AgentClaims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid token claims")
	}

	// Verify the agent ID matches (tokens from previous agent sessions are invalid)
	if claims.AgentID != m.agentID {
		return nil, fmt.Errorf("token was issued by a different agent instance")
	}

	// Verify issuer
	if claims.Issuer != TokenIssuer {
		return nil, fmt.Errorf("invalid token issuer")
	}

	return claims, nil
}

// IsValidToken checks if a token is valid without returning claims
func (m *JWTManager) IsValidToken(tokenString string) bool {
	_, err := m.ValidateToken(tokenString)
	return err == nil
}

// GetAgentID returns the current agent instance ID
func (m *JWTManager) GetAgentID() string {
	return m.agentID
}

// generateJTI generates a unique JWT ID
func generateJTI() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		// Fallback to timestamp-based ID
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

// TokenInfo is a human-readable summary of a token, used by debug/status endpoints.
type TokenInfo struct {
	Valid     bool      `json:"valid"`
	AgentID   string    `json:"agent_id,omitempty"`
	Origin    string    `json:"origin,omitempty"`
	IssuedAt  time.Time `json:"issued_at,omitempty"`
	ExpiresAt time.Time `json:"expires_at,omitempty"`
	Error     string    `json:"error,omitempty"`
}

// GetTokenInfo extracts information from a token for debugging/display.
// Unlike ValidateToken, it returns structured info even for invalid tokens.
func (m *JWTManager) GetTokenInfo(tokenString string) TokenInfo {
	claims, err := m.ValidateToken(tokenString)
	if err != nil {
		return TokenInfo{
			Valid: false,
			Error: err.Error(),
		}
	}

	info := TokenInfo{
		Valid:   true,
		AgentID: claims.AgentID,
		Origin:  claims.Origin,
	}

	if claims.IssuedAt != nil {
		info.IssuedAt = claims.IssuedAt.Time
	}
	if claims.ExpiresAt != nil {
		info.ExpiresAt = claims.ExpiresAt.Time
	}

	return info
}
