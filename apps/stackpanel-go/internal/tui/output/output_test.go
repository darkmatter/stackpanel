package output

import (
	"strings"
	"testing"
)

func TestBuffer(t *testing.T) {
	buf := NewBuffer()

	// Test initial state
	if !buf.IsEmpty() {
		t.Error("New buffer should be empty")
	}

	// Test writing to stdout
	n, err := buf.WriteStdout([]byte("hello stdout"))
	if err != nil {
		t.Errorf("WriteStdout error: %v", err)
	}
	if n != 12 {
		t.Errorf("WriteStdout returned %d, want 12", n)
	}

	// Test writing to stderr
	n, err = buf.WriteStderr([]byte("hello stderr"))
	if err != nil {
		t.Errorf("WriteStderr error: %v", err)
	}
	if n != 12 {
		t.Errorf("WriteStderr returned %d, want 12", n)
	}

	// Check content
	if buf.Stdout() != "hello stdout" {
		t.Errorf("Stdout = %q, want %q", buf.Stdout(), "hello stdout")
	}
	if buf.Stderr() != "hello stderr" {
		t.Errorf("Stderr = %q, want %q", buf.Stderr(), "hello stderr")
	}

	// Combined should have both
	combined := buf.Combined()
	if !strings.Contains(combined, "hello stdout") {
		t.Error("Combined should contain stdout")
	}
	if !strings.Contains(combined, "hello stderr") {
		t.Error("Combined should contain stderr")
	}

	// Test Len
	if buf.Len() != 24 {
		t.Errorf("Len = %d, want 24", buf.Len())
	}

	// Test IsEmpty
	if buf.IsEmpty() {
		t.Error("Buffer should not be empty after writes")
	}

	// Test Reset
	buf.Reset()
	if !buf.IsEmpty() {
		t.Error("Buffer should be empty after reset")
	}
	if buf.Stdout() != "" {
		t.Error("Stdout should be empty after reset")
	}
	if buf.Stderr() != "" {
		t.Error("Stderr should be empty after reset")
	}
}

func TestBufferWriters(t *testing.T) {
	buf := NewBuffer()

	// Test StdoutWriter
	stdoutW := buf.StdoutWriter()
	n, err := stdoutW.Write([]byte("via writer"))
	if err != nil {
		t.Errorf("StdoutWriter.Write error: %v", err)
	}
	if n != 10 {
		t.Errorf("StdoutWriter.Write returned %d, want 10", n)
	}
	if buf.Stdout() != "via writer" {
		t.Errorf("Stdout = %q, want %q", buf.Stdout(), "via writer")
	}

	// Test StderrWriter
	stderrW := buf.StderrWriter()
	stderrW.Write([]byte("error via writer"))
	if buf.Stderr() != "error via writer" {
		t.Errorf("Stderr = %q, want %q", buf.Stderr(), "error via writer")
	}
}

func TestBufferBytes(t *testing.T) {
	buf := NewBuffer()
	buf.WriteStdout([]byte("stdout"))
	buf.WriteStderr([]byte("stderr"))

	if string(buf.StdoutBytes()) != "stdout" {
		t.Error("StdoutBytes mismatch")
	}
	if string(buf.StderrBytes()) != "stderr" {
		t.Error("StderrBytes mismatch")
	}
	if len(buf.CombinedBytes()) != 12 {
		t.Errorf("CombinedBytes length = %d, want 12", len(buf.CombinedBytes()))
	}
}

func TestCaptureWithWriters(t *testing.T) {
	stdout, stderr, getBuffer := CaptureWithWriters()

	stdout.Write([]byte("captured stdout\n"))
	stderr.Write([]byte("captured stderr\n"))

	buf := getBuffer()
	if !strings.Contains(buf.Stdout(), "captured stdout") {
		t.Error("CaptureWithWriters should capture stdout")
	}
	if !strings.Contains(buf.Stderr(), "captured stderr") {
		t.Error("CaptureWithWriters should capture stderr")
	}
}

func TestTeeBuffer(t *testing.T) {
	// Create a buffer to tee to
	var teeBuf strings.Builder

	tee := NewTeeBuffer(&teeBuf, &teeBuf)
	tee.WriteStdout([]byte("teed stdout"))

	// Should be in main buffer
	if tee.Stdout() != "teed stdout" {
		t.Errorf("TeeBuffer.Stdout = %q, want %q", tee.Stdout(), "teed stdout")
	}

	// Should also be in tee buffer
	if !strings.Contains(teeBuf.String(), "teed stdout") {
		t.Error("Tee buffer should contain output")
	}
}

func TestViewerModel(t *testing.T) {
	content := "Test content for viewer"
	viewer := NewViewerModel(content)

	if viewer.Content() != content {
		t.Errorf("Content = %q, want %q", viewer.Content(), content)
	}

	// Test with options
	viewer = NewViewerModel(content,
		WithTitle("Test Title"),
		WithMarkdown(),
		WithShowHelp(false),
	)

	if viewer.title != "Test Title" {
		t.Errorf("title = %q, want %q", viewer.title, "Test Title")
	}
	if !viewer.isMarkdown {
		t.Error("isMarkdown should be true")
	}
	if viewer.showHelp {
		t.Error("showHelp should be false")
	}
}

func TestViewerModelSetters(t *testing.T) {
	viewer := NewViewerModel("initial")

	viewer.SetContent("updated content")
	if viewer.Content() != "updated content" {
		t.Errorf("Content after SetContent = %q, want %q", viewer.Content(), "updated content")
	}

	viewer.SetTitle("New Title")
	if viewer.title != "New Title" {
		t.Errorf("title after SetTitle = %q, want %q", viewer.title, "New Title")
	}

	viewer.SetMarkdown(true)
	if !viewer.isMarkdown {
		t.Error("isMarkdown should be true after SetMarkdown(true)")
	}
}

func TestSimpleViewer(t *testing.T) {
	viewer := NewSimpleViewer("Title", "Content")

	if viewer.title != "Title" {
		t.Errorf("title = %q, want %q", viewer.title, "Title")
	}
	if viewer.content != "Content" {
		t.Errorf("content = %q, want %q", viewer.content, "Content")
	}

	// View should contain title and content
	view := viewer.View()
	if !strings.Contains(view, "Title") {
		t.Error("View should contain title")
	}
	if !strings.Contains(view, "Content") {
		t.Error("View should contain content")
	}
	if !strings.Contains(view, "Press any key") {
		t.Error("View should contain help text")
	}
}

func TestViewerModelView(t *testing.T) {
	viewer := NewViewerModel("Test content", WithTitle("Test"))

	// Before initialization, view shows loading
	view := viewer.View()
	if !strings.Contains(view, "Initializing") {
		t.Error("Uninitialized viewer should show initializing message")
	}
}
