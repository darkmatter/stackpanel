// Package common provides shared utilities for the stackpanel CLI and agent,
// including a unified logging facade that renders through Charmbracelet's
// styled output for consistent terminal aesthetics.
package common

import (
	"os"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/log"
	"go.uber.org/zap"
	"go.uber.org/zap/buffer"
	"go.uber.org/zap/zapcore"
)

// Lipgloss styles for direct terminal rendering outside the logger.
// Used by CLI commands that need styled output without going through zap.
var (
	StyleInfo    = lipgloss.NewStyle().Foreground(lipgloss.Color("#00afff"))
	StyleWarning = lipgloss.NewStyle().Foreground(lipgloss.Color("#ffaf00"))
	StyleError   = lipgloss.NewStyle().Foreground(lipgloss.Color("#ff5f5f")).Bold(true)
	StyleDebug   = lipgloss.NewStyle().Foreground(lipgloss.Color("#888888"))
)

var logger *zap.SugaredLogger
var charmLog = log.NewWithOptions(os.Stderr, log.Options{ReportTimestamp: false})

func init() {
	// Wire zap through Charmbracelet's log renderer so all logging—whether from
	// our code or third-party libs using zap globals—gets styled terminal output.
	logger = zap.New(zapcore.NewCore(
		&charmEncoder{zapcore.NewConsoleEncoder(zapcore.EncoderConfig{})},
		zapcore.AddSync(os.Stderr),
		zapcore.DebugLevel,
	)).Sugar()
	zap.ReplaceGlobals(logger.Desugar())
}

// charmEncoder is a zapcore.Encoder adapter that delegates actual rendering to
// Charmbracelet's log package. The embedded ConsoleEncoder is unused for output;
// it only satisfies the interface. All formatting comes from charmLog.
type charmEncoder struct{ zapcore.Encoder }

func (e *charmEncoder) Clone() zapcore.Encoder { return &charmEncoder{e.Encoder.Clone()} }

// EncodeEntry routes zap log entries to charmLog for styled output.
// Returns an empty buffer since charmLog writes directly to stderr.
func (e *charmEncoder) EncodeEntry(ent zapcore.Entry, fields []zapcore.Field) (*buffer.Buffer, error) {
	switch ent.Level {
	case zapcore.DebugLevel:
		charmLog.Debug(ent.Message)
	case zapcore.InfoLevel:
		charmLog.Info(ent.Message)
	case zapcore.WarnLevel:
		charmLog.Warn(ent.Message)
	default:
		charmLog.Error(ent.Message)
	}
	return buffer.NewPool().Get(), nil
}

// L returns the package-level sugared logger for structured logging.
func L() *zap.SugaredLogger { return logger }

// Structured logging with key-value pairs: common.Info("connected", "port", 8080)
func Debug(msg string, args ...any) { zap.S().Debugw(msg, args...) }
func Info(msg string, args ...any)  { zap.S().Infow(msg, args...) }
func Warn(msg string, args ...any)  { zap.S().Warnw(msg, args...) }
func Error(msg string, args ...any) { zap.S().Errorw(msg, args...) }
func Fatal(msg string, args ...any) { zap.S().Fatalw(msg, args...) }
func Print(msg string, args ...any) { zap.S().Infow(msg, args...) }

// Printf-style formatted logging: common.Infof("listening on :%d", port)
func Debugf(t string, args ...any) { zap.S().Debugf(t, args...) }
func Infof(t string, args ...any)  { zap.S().Infof(t, args...) }
func Warnf(t string, args ...any)  { zap.S().Warnf(t, args...) }
func Errorf(t string, args ...any) { zap.S().Errorf(t, args...) }
func Fatalf(t string, args ...any) { zap.S().Fatalf(t, args...) }
func Printf(t string, args ...any) { zap.S().Infof(t, args...) }

// With returns a child logger with additional context fields baked in.
func With(args ...any) *zap.SugaredLogger {
	return zap.S().With(args...)
}
