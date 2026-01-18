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

// Success prints a success message with a green checkmark.
func Success(msg string) {
	Green.Print("✓ ")
	fmt.Println(msg)
}

// Info prints an informational message with a purple arrow.
func Info(msg string) {
	Purple.Print("→ ")
	fmt.Println(msg)
}

// Warning prints a warning message with a yellow warning sign.
func Warning(msg string) {
	Yellow.Print("⚠ ")
	fmt.Println(msg)
}

// Error prints an error message with a red X to stderr.
func Error(msg string) {
	Red.Print("✗ ")
	fmt.Fprintln(os.Stderr, msg)
}

// Dimmed prints a dimmed/faded message.
func Dimmed(msg string) {
	DimC.Println(msg)
}

// SetNoColor disables colored output globally.
func SetNoColor(noColor bool) {
	color.NoColor = noColor
}
