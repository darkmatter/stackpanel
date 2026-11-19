//go:build darwin || linux

package server

import (
	"context"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

// The process-compose launcher gives the service an inherited, read-only fd 9
// for this marker. This is local process attribution, not a boundary against
// hostile same-UID executables (which can also read the agent's credentials).
// Never inspect process environments, argv, or traffic to establish identity.
type moduleProxyPeer struct {
	address, marker, dev, inode, uid, lsof string
}

func newModuleProxyPeer(
	root, module, service, address string,
) (moduleProxyPeer, error) {
	var peer moduleProxyPeer
	if !filepath.IsAbs(root) || !moduleProxySegment(module) ||
		!moduleProxySegment(service) {
		return peer, errModuleProxyIdentity
	}
	// Open directory components individually with no-follow. In particular a
	// marker symlink/hard link must not alias another module or checkout.
	real, err := filepath.EvalSymlinks(root)
	if err != nil {
		return peer, errModuleProxyIdentity
	}
	fd, err := unix.Open(
		real,
		unix.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW|unix.O_CLOEXEC,
		0,
	)
	if err != nil {
		return peer, errModuleProxyIdentity
	}
	for _, part := range []string{".stack", "state", "proxy", module} {
		next, err := unix.Openat(
			fd,
			part,
			unix.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW|unix.O_CLOEXEC,
			0,
		)
		unix.Close(fd)
		if err != nil {
			return peer, errModuleProxyIdentity
		}
		fd = next
	}
	defer unix.Close(fd)
	var stat unix.Stat_t
	leaf := service + ".identity"
	if unix.Fstatat(fd, leaf, &stat, unix.AT_SYMLINK_NOFOLLOW) != nil || stat.Mode&unix.S_IFMT != unix.S_IFREG ||
		stat.Uid != uint32(os.Geteuid()) || stat.Mode&0o7777 != 0o600 ||
		stat.Nlink != 1 {
		return peer, errModuleProxyIdentity
	}
	binary := moduleProxyLsof()
	if binary == "" {
		return peer, errModuleProxyIdentity
	}
	return moduleProxyPeer{
		address: address,
		marker:  filepath.Join(real, ".stack", "state", "proxy", module, leaf),
		dev: "0x" + strconv.FormatUint(
			uint64(stat.Dev),
			16,
		),
		inode: strconv.FormatUint(stat.Ino, 10),
		uid:   strconv.Itoa(os.Geteuid()),
		lsof:  binary,
	}, nil
}

func moduleProxyLsof() string {
	for _, path := range []string{"/usr/sbin/lsof", "/usr/bin/lsof", "/run/current-system/sw/bin/lsof"} {
		if info, err := os.Stat(path); err == nil && info.Mode().IsRegular() {
			return path
		}
	}
	// A Nix shell needn't install lsof system-wide. Never execute a binary
	// from a checkout, a user-writable PATH entry or the process's current dir.
	if path, err := exec.LookPath("lsof"); err == nil {
		if real, err := filepath.EvalSymlinks(
			path,
		); err == nil &&
			strings.HasPrefix(real, "/nix/store/") {
			return real
		}
	}
	return ""
}

func (p moduleProxyPeer) dial(
	ctx context.Context,
	network, addr string,
) (net.Conn, error) {
	if network != "tcp" || addr != p.address {
		return nil, errModuleProxyIdentity
	}
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	// Check the listening owner before even opening a socket. Then verify the
	// *accepted* connection using both endpoints. A port reused between the two
	// checks can never receive HTTP bytes. No second dial after verification.
	if !p.ownsSocket(ctx, p.address, "LISTEN") {
		return nil, errModuleProxyIdentity
	}
	conn, err := (&net.Dialer{}).DialContext(ctx, "tcp4", p.address)
	if err != nil {
		return nil, errModuleProxyIdentity
	}
	if !p.ownsSocket(ctx, p.address+"->"+conn.LocalAddr().String(), "ESTABLISHED") {
		conn.Close()
		return nil, errModuleProxyIdentity
	}
	return conn, nil
}

func (p moduleProxyPeer) ownsSocket(ctx context.Context, endpoint, state string) bool {
	_, port, err := net.SplitHostPort(p.address)
	if err != nil {
		return false
	}
	// OR selectors: include records for both the marker and relevant TCP FDs.
	// -nP disables DNS/service lookups. A bounded machine-readable snapshot;
	// don't send output, paths or stderr to either HTTP clients or agent logs.
	cmd := exec.CommandContext(
		ctx,
		p.lsof,
		"-nP",
		"-F0pufatDinT",
		"-i4TCP:"+port,
		"--",
		p.marker,
	)
	cmd.Env = []string{"LC_ALL=C"}
	out, err := cmd.StdoutPipe()
	if err != nil || cmd.Start() != nil {
		return false
	}
	const max = 1 << 20
	var data strings.Builder
	n, err := io.Copy(&data, io.LimitReader(out, max+1))
	if err != nil || n > max {
		_ = cmd.Process.Kill()
	}
	if cmd.Wait() != nil || err != nil || n > max {
		return false
	}
	return p.matchesSnapshot(data.String(), endpoint, state, port)
}

func (p moduleProxyPeer) matchesSnapshot(data, endpoint, state, port string) bool {
	owners := 0
	var pid, uid string
	var marker, socket bool
	ownerOK := func() bool {
		if !socket {
			return true
		}
		owners++
		return owners == 1 && marker && uid == p.uid && pid != "" &&
			pid != strconv.Itoa(os.Getpid())
	}
	// lsof -F0: fields end in NUL, process and file records in NUL/newline.
	for record := range strings.SplitSeq(data, "\x00\n") {
		if len(record) == 0 {
			continue
		}
		if record[0] == 'p' {
			if !ownerOK() {
				return false
			}
			uid, marker, socket = "", false, false
		}
		var fd, access, kind, dev, ino, name, tcp string
		for field := range strings.SplitSeq(record, "\x00") {
			if len(field) < 2 {
				continue
			}
			v := field[1:]
			switch field[0] {
			case 'p':
				pid = v
			case 'u':
				uid = v
			case 'f':
				fd = v
			case 'a':
				access = v
			case 't':
				kind = v
			case 'D':
				dev = v
			case 'i':
				ino = v
			case 'n':
				name = v
			case 'T':
				if strings.HasPrefix(v, "ST=") {
					tcp = v[3:]
				}
			}
		}
		if fd == "9" && access == "r" && kind == "REG" && dev == p.dev && ino == p.inode {
			marker = true
		}
		if kind == "IPv4" && tcp == state &&
			(name == endpoint || state == "LISTEN" && name == "*:"+port) {
			socket = true
		}
	}
	return ownerOK() && owners == 1
}
