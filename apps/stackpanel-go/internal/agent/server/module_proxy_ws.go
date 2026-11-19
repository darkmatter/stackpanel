package server

import (
	"context"
	"encoding/base64"
	"io"
	"math"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

// Only WebSocket is an upgrade capability. Reject ambiguous handshakes and
// Connection nominations rather than accidentally forwarding hop-only fields.
func moduleProxyHandshake(r *http.Request) (upgrade, valid bool) {
	for _, list := range r.Header.Values("Connection") {
		for token := range strings.SplitSeq(list, ",") {
			switch strings.ToLower(strings.TrimSpace(token)) {
			case "upgrade":
				upgrade = true
			case "close", "keep-alive":
			default:
				return false, false
			}
		}
	}
	if !upgrade {
		for k := range r.Header {
			if k == "Upgrade" || strings.HasPrefix(k, "Sec-Websocket-") {
				return false, false
			}
		}
		return false, true
	}
	if r.Method != http.MethodGet || r.ProtoMajor != 1 || r.ProtoMinor != 1 || r.Close ||
		len(
			r.Header.Values("Upgrade"),
		) != 1 || !strings.EqualFold(r.Header.Get("Upgrade"), "websocket") ||
		len(
			r.Header.Values("Sec-WebSocket-Version"),
		) != 1 || r.Header.Get("Sec-WebSocket-Version") != "13" ||
		len(
			r.Header.Values("Sec-WebSocket-Key"),
		) != 1 || len(r.Header.Values("Sec-WebSocket-Protocol")) != 0 {
		return false, false
	}
	key := r.Header.Get("Sec-WebSocket-Key")
	var decoded [18]byte // maximum decoded size for a padded 24-byte key
	if len(key) != 24 {
		return false, false
	}
	n, err := base64.StdEncoding.Strict().Decode(decoded[:], []byte(key))
	return true, err == nil && n == 16
}

// Gorilla reads HTTP upgrade headers directly from its connection. Bound that
// read before the validated handshake switches to message framing/read limits.
type moduleProxyHandshakeConn struct {
	net.Conn
	reader io.LimitedReader
}

func (c *moduleProxyHandshakeConn) Read(
	p []byte,
) (int, error) {
	return c.reader.Read(p)
}

func (s *Server) serveModuleProxyWebSocket(
	w http.ResponseWriter,
	r *http.Request,
	target url.URL,
	peer moduleProxyPeer,
) {
	var handshake *moduleProxyHandshakeConn
	dialer := websocket.Dialer{
		HandshakeTimeout: 10 * time.Second,
		NetDialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			conn, err := peer.dial(ctx, network, addr)
			if err != nil {
				return nil, err
			}
			handshake = &moduleProxyHandshakeConn{
				Conn:   conn,
				reader: io.LimitedReader{R: conn, N: 32 << 10},
			}
			return handshake, nil
		},
	}
	// Independent handshakes, not a raw upgrade tunnel: neither endpoint can
	// set the peer's headers, negotiate unsolicited extensions or redirect.
	upstream, resp, err := dialer.DialContext(r.Context(), target.String(), nil)
	if resp != nil {
		defer resp.Body.Close()
	}
	if err != nil {
		http.Error(w, "service websocket unavailable", http.StatusBadGateway)
		return
	}
	defer upstream.Close()
	if len(resp.Header.Values("Sec-WebSocket-Protocol")) != 0 || len(resp.Header.Values("Sec-WebSocket-Extensions")) != 0 ||
		len(resp.Trailer) != 0 ||
		len(resp.Header.Values("Trailer")) != 0 {
		http.Error(w, "unsupported service handshake", http.StatusBadGateway)
		return
	}
	handshake.reader.N = math.MaxInt64
	upgrader := websocket.Upgrader{
		HandshakeTimeout: 10 * time.Second,
		// The parent route already enforces the agent's origin policy. Gorilla's
		// default is a different policy (same Host) and would reject Studio.
		CheckOrigin: func(*http.Request) bool { return true },
	}
	client, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer client.Close()
	client.SetReadLimit(moduleProxyRequestLimit)
	upstream.SetReadLimit(moduleProxyResponseLimit)
	done := make(chan struct{}, 2)
	go relayModuleProxyMessages(upstream, client, done)
	go relayModuleProxyMessages(client, upstream, done)
	select {
	case <-done:
	case <-r.Context().Done():
	case <-s.done: // http.Server.Shutdown does not close hijacked connections
	}
	// Closing both endpoints unblocks the other direction as well.
}

func relayModuleProxyMessages(dst, src *websocket.Conn, done chan<- struct{}) {
	defer func() { done <- struct{}{} }()
	for {
		kind, reader, err := src.NextReader()
		if err != nil {
			if websocket.IsCloseError(
				err,
				websocket.CloseNormalClosure,
				websocket.CloseGoingAway,
			) {
				_ = dst.WriteControl(
					websocket.CloseMessage,
					websocket.FormatCloseMessage(err.(*websocket.CloseError).Code, ""),
					time.Now().Add(time.Second),
				)
			}
			return
		}
		_ = dst.SetWriteDeadline(time.Now().Add(30 * time.Second))
		writer, err := dst.NextWriter(kind)
		if err != nil {
			return
		}
		if _, err := io.Copy(writer, reader); err != nil {
			return
		}
		if err := writer.Close(); err != nil {
			return
		}
	}
}
