package server

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	// TokenExpiration is how long tokens are valid for
	TokenExpiration = 30 * 24 * time.Hour // 30 days

	// Issuer identifies tokens as coming from stackpanel agent
	TokenIssuer = "stackpanel-agent"
)

// AgentClaims contains the JWT claims for agent tokens
type AgentClaims struct {
	jwt.RegisteredClaims

	// AgentID is a unique identifier for this agent instance
	AgentID string `json:"agent_id"`

	// Origin is the allowed origin for this token (optional)
	Origin string `json:"origin,omitempty"`
}

// JWTManager handles JWT token generation and validation
type JWTManager struct {
	// signingKey is the secret key used to sign tokens
	signingKey []byte

	// agentID is a unique identifier for this agent instance
	// It changes each time the agent restarts, invalidating old tokens
	agentID string
}

// NewJWTManager creates a new JWT manager with a random signing key and agent ID
func NewJWTManager() (*JWTManager, error) {
	// Generate a random 32-byte signing key
	signingKey := make([]byte, 32)
	if _, err := rand.Read(signingKey); err != nil {
		return nil, fmt.Errorf("failed to generate signing key: %w", err)
	}

	// Generate a random agent ID (16 bytes = 22 base64 chars)
	agentIDBytes := make([]byte, 16)
	if _, err := rand.Read(agentIDBytes); err != nil {
		return nil, fmt.Errorf("failed to generate agent ID: %w", err)
	}
	agentID := base64.RawURLEncoding.EncodeToString(agentIDBytes)

	return &JWTManager{
		signingKey: signingKey,
		agentID:    agentID,
	}, nil
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

// ValidateToken validates a JWT token and returns the claims if valid
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

// TokenInfo contains information about a token for display purposes
type TokenInfo struct {
	Valid     bool      `json:"valid"`
	AgentID   string    `json:"agent_id,omitempty"`
	Origin    string    `json:"origin,omitempty"`
	IssuedAt  time.Time `json:"issued_at,omitempty"`
	ExpiresAt time.Time `json:"expires_at,omitempty"`
	Error     string    `json:"error,omitempty"`
}

// GetTokenInfo extracts information from a token without full validation
// This is useful for debugging and displaying token status
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
