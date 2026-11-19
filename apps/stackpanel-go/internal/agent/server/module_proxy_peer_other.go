//go:build !darwin && !linux

package server

import (
	"context"
	"net"
)

// No portable kernel evidence of which process owns an accepted TCP socket.
// Never degrade to a bare dial on an unsupported platform.
type moduleProxyPeer struct{}

func newModuleProxyPeer(_, _, _, _ string) (moduleProxyPeer, error) {
	return moduleProxyPeer{}, errModuleProxyIdentity
}

func (moduleProxyPeer) dial(context.Context, string, string) (net.Conn, error) {
	return nil, errModuleProxyIdentity
}
