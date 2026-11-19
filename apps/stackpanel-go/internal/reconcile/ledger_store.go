package reconcile

import (
	"bytes"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"syscall"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixdata"
)

// info == nil is a snapshot too: creating a new ledger must not overwrite
// one that appeared since load.
type ledgerFile struct {
	info os.FileInfo
	data []byte
}

func sameLedgerFile(a, b os.FileInfo) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return os.SameFile(a, b) && a.Mode() == b.Mode() && a.Size() == b.Size() &&
		a.ModTime().Equal(b.ModTime())
}

func readLedgerFile(dir *os.Root, writable bool) (ledgerFile, error) {
	before, err := dir.Lstat(ledgerName)
	if errors.Is(err, os.ErrNotExist) {
		return ledgerFile{}, nil
	}
	if err != nil {
		return ledgerFile{}, err
	}
	if !before.Mode().IsRegular() {
		return ledgerFile{}, fmt.Errorf("%s is not a regular file", ledgerName)
	}
	flags := os.O_RDONLY
	if writable {
		if before.Mode().Perm()&0o222 == 0 {
			return ledgerFile{}, fmt.Errorf("%s is read-only: %w", ledgerName, os.ErrPermission)
		}
		flags = os.O_RDWR // preserve WriteFile's access check without truncating
	}
	f, err := dir.OpenFile(ledgerName, flags|syscall.O_NONBLOCK, 0)
	if err != nil {
		return ledgerFile{}, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return ledgerFile{}, err
	}
	if !sameLedgerFile(before, info) {
		return ledgerFile{}, fmt.Errorf("%s changed during open", ledgerName)
	}
	data, err := io.ReadAll(f)
	if err != nil {
		return ledgerFile{}, err
	}
	after, err := dir.Lstat(ledgerName)
	if err != nil {
		return ledgerFile{}, err
	}
	if !sameLedgerFile(info, after) {
		return ledgerFile{}, fmt.Errorf("%s changed during read", ledgerName)
	}
	return ledgerFile{info: info, data: data}, nil
}

func (s ledgerFile) check(dir *os.Root) error {
	current, err := readLedgerFile(dir, true)
	if err != nil {
		return err
	}
	if !sameLedgerFile(s.info, current.info) || !bytes.Equal(s.data, current.data) {
		return fmt.Errorf("%s changed since load; refusing to overwrite it", ledgerName)
	}
	return nil
}

func (l *Ledger) save(root string) error {
	project, err := os.OpenRoot(root)
	if err != nil {
		return err
	}
	defer project.Close()
	info, err := project.Stat(".")
	if err != nil {
		return err
	}
	if !os.SameFile(info, l.rootInfo) {
		return fmt.Errorf("%s is not the project used to load %s", root, l.path)
	}
	// Encode the v1 storage format before creating anything on disk.
	data, err := json.MarshalIndent(struct {
		Version int                    `json:"version"`
		Seen    map[string]LedgerEntry `json:"seen"`
	}{ledgerVersion, l.Seen}, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')

	dir, err := project.OpenRoot(nixdata.ConfigDirName)
	if errors.Is(err, os.ErrNotExist) && l.configInfo == nil {
		if err := project.Mkdir(nixdata.ConfigDirName, 0o755); err != nil {
			return err
		}
		dir, err = project.OpenRoot(nixdata.ConfigDirName)
	}
	if err != nil {
		return err
	}
	defer dir.Close()
	info, err = dir.Stat(".")
	if err != nil {
		return err
	}
	if l.configInfo != nil && !os.SameFile(l.configInfo, info) {
		return fmt.Errorf("config directory for %s changed since load", l.path)
	}
	staged, err := l.commit(dir, data)
	if err != nil {
		return fmt.Errorf("save %s: %w", l.path, err)
	}
	l.configInfo = info
	l.Version = ledgerVersion
	l.current = staged
	return nil
}

func (l *Ledger) commit(dir *os.Root, data []byte) (ledgerFile, error) {
	// Stage and publish inside the same pinned config directory.
	tmp := ".reconcile-" + rand.Text()
	mode := os.FileMode(0o644)
	if l.current.info != nil {
		mode = l.current.info.Mode().Perm()
	}
	f, err := dir.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode)
	if err != nil {
		return ledgerFile{}, err
	}
	defer dir.Remove(tmp)
	_, err = f.Write(data)
	if err == nil && l.current.info != nil {
		err = f.Chmod(mode) // don't let today's umask change an existing ledger
	}
	if err == nil {
		err = f.Sync()
	}
	var info os.FileInfo
	if err == nil {
		info, err = f.Stat()
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return ledgerFile{}, err
	}

	// Stage first, then check immediately before publication. The project lock
	// serializes participating writers; POSIX has no conditional rename over
	// an existing file. Link gives us atomic no-clobber for the absent case.
	if err := l.current.check(dir); err != nil {
		return ledgerFile{}, err
	}
	if l.current.info == nil {
		err = dir.Link(tmp, ledgerName)
	} else {
		err = dir.Rename(tmp, ledgerName)
	}
	if err != nil {
		return ledgerFile{}, err
	}
	return ledgerFile{info: info, data: data}, nil
}
