// ws.go holds the WebSocket upgrader used by the process-compose log
// streaming endpoint.
package server

import (
	"net/http"

	"github.com/gorilla/websocket"
)

// wsUpgrader upgrades process-compose log streaming connections.
var wsUpgrader = websocket.Upgrader{
	ReadBufferSize:  32 * 1024,
	WriteBufferSize: 32 * 1024,
	// CheckOrigin only requires an Origin header; the origin allowlist is
	// applied by requireAuth/withAllowedOrigin on routes that use them.
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		// Require Origin for browser-based WebSocket connections.
		return origin != ""
	},
}
