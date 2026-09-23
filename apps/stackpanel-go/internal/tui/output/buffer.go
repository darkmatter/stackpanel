// Package output provides stdout/stderr capture and paged viewing for TUI command execution.
package output

import (
	"bytes"
	"io"
	"os"
	"sync"
)

// Buffer captures stdout and stderr from command execution.
// All methods are goroutine-safe. The combined buffer preserves interleaved
// ordering so callers see output in the same order it was written.
type Buffer struct {
	mu     sync.RWMutex
	stdout bytes.Buffer
	stderr bytes.Buffer
	// combined stores interleaved stdout/stderr in order received
	combined bytes.Buffer
}

// NewBuffer creates a new output buffer
func NewBuffer() *Buffer {
	return &Buffer{}
}

// Write writes to both stdout buffer and combined buffer
func (b *Buffer) Write(p []byte) (n int, err error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.combined.Write(p)
	return b.stdout.Write(p)
}

// WriteStdout writes to stdout buffer
func (b *Buffer) WriteStdout(p []byte) (n int, err error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.combined.Write(p)
	return b.stdout.Write(p)
}

// WriteStderr writes to stderr buffer
func (b *Buffer) WriteStderr(p []byte) (n int, err error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.combined.Write(p)
	return b.stderr.Write(p)
}

// Stdout returns the captured stdout content
func (b *Buffer) Stdout() string {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.stdout.String()
}

// Stderr returns the captured stderr content
func (b *Buffer) Stderr() string {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.stderr.String()
}

// Combined returns the combined stdout/stderr content in order received
func (b *Buffer) Combined() string {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.combined.String()
}

// StdoutBytes returns the captured stdout as bytes
func (b *Buffer) StdoutBytes() []byte {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.stdout.Bytes()
}

// StderrBytes returns the captured stderr as bytes
func (b *Buffer) StderrBytes() []byte {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.stderr.Bytes()
}

// CombinedBytes returns the combined output as bytes
func (b *Buffer) CombinedBytes() []byte {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.combined.Bytes()
}

// Reset clears all buffers
func (b *Buffer) Reset() {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.stdout.Reset()
	b.stderr.Reset()
	b.combined.Reset()
}

// Len returns the total length of combined output
func (b *Buffer) Len() int {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.combined.Len()
}

// IsEmpty returns true if no output has been captured
func (b *Buffer) IsEmpty() bool {
	return b.Len() == 0
}

// StdoutWriter returns an io.Writer that writes to stdout buffer
func (b *Buffer) StdoutWriter() io.Writer {
	return &stdoutWriter{b: b}
}

// StderrWriter returns an io.Writer that writes to stderr buffer
func (b *Buffer) StderrWriter() io.Writer {
	return &stderrWriter{b: b}
}

type stdoutWriter struct {
	b *Buffer
}

func (w *stdoutWriter) Write(p []byte) (n int, err error) {
	return w.b.WriteStdout(p)
}

type stderrWriter struct {
	b *Buffer
}

func (w *stderrWriter) Write(p []byte) (n int, err error) {
	return w.b.WriteStderr(p)
}

// Capture redirects os.Stdout and os.Stderr to pipes for the duration of fn,
// collecting all output into a Buffer. This is inherently process-global — it
// temporarily replaces the file descriptors, so concurrent Capture calls will
// interfere with each other. Used by the navigation model to capture Cobra
// command output for display in the output viewer.
func Capture(fn func()) *Buffer {
	buf := NewBuffer()

	// Save original stdout/stderr
	oldStdout := os.Stdout
	oldStderr := os.Stderr

	// Create pipes
	rOut, wOut, _ := os.Pipe()
	rErr, wErr, _ := os.Pipe()

	// Replace stdout/stderr
	os.Stdout = wOut
	os.Stderr = wErr

	// Copy pipe output to buffer in goroutines
	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		io.Copy(buf.StdoutWriter(), rOut)
	}()

	go func() {
		defer wg.Done()
		io.Copy(buf.StderrWriter(), rErr)
	}()

	// Execute the function
	fn()

	// Close write ends and restore
	wOut.Close()
	wErr.Close()
	os.Stdout = oldStdout
	os.Stderr = oldStderr

	// Wait for copy goroutines to finish
	wg.Wait()

	// Close read ends
	rOut.Close()
	rErr.Close()

	return buf
}
