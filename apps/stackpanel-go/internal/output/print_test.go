package output

import (
	"testing"

	"github.com/fatih/color"
)

func init() {
	// Disable colors for testing to get predictable output
	color.NoColor = true
}

// TestSuccess verifies the Success function doesn't panic.
func TestSuccess(t *testing.T) {
	defer func() {
		if r := recover(); r != nil {
			t.Errorf("Success() panicked: %v", r)
		}
	}()
	Success("test message")
}

// TestInfo verifies the Info function doesn't panic.
func TestInfo(t *testing.T) {
	defer func() {
		if r := recover(); r != nil {
			t.Errorf("Info() panicked: %v", r)
		}
	}()
	Info("info message")
}

// TestWarning verifies the Warning function doesn't panic.
func TestWarning(t *testing.T) {
	defer func() {
		if r := recover(); r != nil {
			t.Errorf("Warning() panicked: %v", r)
		}
	}()
	Warning("warning message")
}

// TestError verifies the Error function doesn't panic.
func TestError(t *testing.T) {
	defer func() {
		if r := recover(); r != nil {
			t.Errorf("Error() panicked: %v", r)
		}
	}()
	Error("error message")
}

// TestDimmed verifies the Dimmed function doesn't panic.
func TestDimmed(t *testing.T) {
	defer func() {
		if r := recover(); r != nil {
			t.Errorf("Dimmed() panicked: %v", r)
		}
	}()
	Dimmed("dim message")
}

// TestSetNoColor verifies the SetNoColor function works correctly.
func TestSetNoColor(t *testing.T) {
	originalValue := color.NoColor

	SetNoColor(true)
	if !color.NoColor {
		t.Error("SetNoColor(true) did not set color.NoColor to true")
	}

	SetNoColor(false)
	if color.NoColor {
		t.Error("SetNoColor(false) did not set color.NoColor to false")
	}

	// Restore original value
	color.NoColor = originalValue
}

// TestColorVariablesExist verifies the exported color variables are not nil.
func TestColorVariablesExist(t *testing.T) {
	if Purple == nil {
		t.Error("Purple color is nil")
	}
	if Green == nil {
		t.Error("Green color is nil")
	}
	if Yellow == nil {
		t.Error("Yellow color is nil")
	}
	if Red == nil {
		t.Error("Red color is nil")
	}
	if DimC == nil {
		t.Error("DimC color is nil")
	}
}
