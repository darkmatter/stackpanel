// Package output provides helper functions for formatted CLI output.
package output

import (
	"fmt"
	"os"

	"github.com/fatih/color"
)

var (
	// Colors for styled output (exported for direct use)
	Purple = color.New(color.Attribute(38), color.Attribute(5), color.Attribute(99)) // 256-color purple (code 99)
	Green  = color.New(color.FgGreen)
	Yellow = color.New(color.FgYellow)
	Red    = color.New(color.FgRed)
	DimC   = color.New(color.Faint)
)

// Success prints a success message with a green checkmark to stderr.
func Success(msg string) {
	Green.Fprint(os.Stderr, "✓ ")
	fmt.Fprintln(os.Stderr, msg)
}

// Info prints an informational message with a purple arrow to stderr.
func Info(msg string) {
	Purple.Fprint(os.Stderr, "→ ")
	fmt.Fprintln(os.Stderr, msg)
}

// Warning prints a warning message with a yellow warning sign to stderr.
func Warning(msg string) {
	Yellow.Fprint(os.Stderr, "⚠ ")
	fmt.Fprintln(os.Stderr, msg)
}

// Error prints an error message with a red X to stderr.
func Error(msg string) {
	Red.Print("✗ ")
	fmt.Fprintln(os.Stderr, msg)
}

// Dimmed prints a dimmed/faded message to stderr.
func Dimmed(msg string) {
	DimC.Fprintln(os.Stderr, msg)
}

// SetNoColor disables colored output globally.
func SetNoColor(noColor bool) {
	color.NoColor = noColor
}
