package registry

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"time"
)

// One atomic record prevents a validator for one response from being paired
// with the body of another after interruption or concurrent refreshes.
type cacheRecord struct {
	Checked time.Time `json:"checked"`
	ETag    string    `json:"etag,omitempty"`
	Body    []byte    `json:"body"`
}

func (c *Client) cachePath(kind, uri string, headers map[string]string) string {
	if c.cacheDir == "" {
		return ""
	}
	// encoding/json sorts map keys. Rotating or removing credentials must
	// not reuse a still-fresh response obtained under another identity.
	key, _ := json.Marshal([]any{kind, uri, headers})
	digest := sha256.Sum256(key)
	return filepath.Join(c.cacheDir, hex.EncodeToString(digest[:])+".json")
}

func readBounded(r io.Reader, max int64) ([]byte, error) {
	data, err := io.ReadAll(io.LimitReader(r, max+1))
	if int64(len(data)) > max {
		return nil, fmt.Errorf("response exceeds %d bytes", max)
	}
	return data, err
}

func readRecord(path string, max int64) (cacheRecord, bool) {
	var rec cacheRecord
	if path == "" {
		return rec, false
	}
	f, err := os.Open(path)
	if err != nil {
		return rec, false
	}
	defer f.Close()
	// Body is base64-encoded by encoding/json.
	data, err := readBounded(f, 2*max+4096)
	if err != nil || json.Unmarshal(data, &rec) != nil || rec.Checked.IsZero() ||
		rec.Body == nil ||
		int64(len(rec.Body)) > max {
		return cacheRecord{}, false
	}
	return rec, true
}

func writeRecord(path string, rec cacheRecord) error {
	if path == "" {
		return nil // no user cache directory available
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	f, err := os.CreateTemp(dir, ".refresh-*") // 0600, including private README text
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	err = json.NewEncoder(f).Encode(&rec)
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(f.Name(), path)
}

func fetch[T any](
	ctx context.Context,
	c *Client,
	u *url.URL,
	headers map[string]string,
	kind string,
	limit int64,
	decode func([]byte) (T, error),
	fallback []byte,
) (T, error) {
	var zero T
	if err := ctx.Err(); err != nil {
		return zero, err
	}
	if len(headers) != 0 && !allowCredentials(u) {
		return zero, errors.New("registry credentials require HTTPS or loopback")
	}
	path := c.cachePath(kind, u.String(), headers)
	rec, cached := readRecord(path, limit)
	var previous T
	if cached {
		var err error
		previous, err = decode(rec.Body)
		cached = err == nil
		age := c.now().Sub(rec.Checked)
		if cached && age >= 0 && age < cacheTTL {
			return previous, nil
		}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return zero, err
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	if cached && rec.ETag != "" {
		req.Header.Set("If-None-Match", rec.ETag)
	}
	offline := func(err error) (T, error) {
		if ctx.Err() != nil {
			return zero, ctx.Err()
		}
		if cached {
			return previous, nil
		}
		if fallback != nil {
			return decode(fallback)
		}
		return zero, err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		// url.Error includes the request URI, potentially with signed query params.
		var ue *url.Error
		if errors.As(err, &ue) {
			err = ue.Err
		}
		return offline(err)
	}
	defer resp.Body.Close()
	var value T
	switch {
	case resp.StatusCode == http.StatusNotModified && cached && rec.ETag != "":
		value = previous
		if etag := resp.Header.Get("ETag"); etag != "" {
			rec.ETag = etag
		}
	case resp.StatusCode == http.StatusOK:
		body, err := readBounded(resp.Body, limit)
		if err != nil {
			return zero, err
		}
		value, err = decode(body)
		if err != nil {
			return zero, err // never publish or silently mask a malformed catalog
		}
		rec.Body, rec.ETag = body, resp.Header.Get("ETag")
	case resp.StatusCode >= 500 && resp.StatusCode <= 599:
		return offline(fmt.Errorf("upstream HTTP %d", resp.StatusCode))
	default:
		// Do not substitute cached or public data after denial/removal.
		if path != "" &&
			(resp.StatusCode == 401 || resp.StatusCode == 403 || resp.StatusCode == 404 || resp.StatusCode == 410) {
			if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
				return zero, fmt.Errorf(
					"invalidate cache after HTTP %d: %w",
					resp.StatusCode,
					err,
				)
			}
		}
		return zero, fmt.Errorf("unexpected HTTP %d", resp.StatusCode)
	}
	rec.Checked = c.now()
	// Persistence is an optimization: an unwritable cache must not discard
	// a valid response or a body the upstream just revalidated.
	_ = writeRecord(path, rec)
	return value, nil
}
