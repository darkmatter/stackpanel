package common

import (
	"os"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/log"
	"go.uber.org/zap"
	"go.uber.org/zap/buffer"
	"go.uber.org/zap/zapcore"
)

var (
	StyleInfo    = lipgloss.NewStyle().Foreground(lipgloss.Color("#00afff"))
	StyleWarning = lipgloss.NewStyle().Foreground(lipgloss.Color("#ffaf00"))
	StyleError   = lipgloss.NewStyle().Foreground(lipgloss.Color("#ff5f5f")).Bold(true)
	StyleDebug   = lipgloss.NewStyle().Foreground(lipgloss.Color("#888888"))
)

var logger *zap.SugaredLogger
var charmLog = log.NewWithOptions(os.Stderr, log.Options{ReportTimestamp: false})

func init() {
	logger = zap.New(zapcore.NewCore(
		&charmEncoder{zapcore.NewConsoleEncoder(zapcore.EncoderConfig{})},
		zapcore.AddSync(os.Stderr),
		zapcore.DebugLevel,
	)).Sugar()
	zap.ReplaceGlobals(logger.Desugar())
}

type charmEncoder struct{ zapcore.Encoder }

func (e *charmEncoder) Clone() zapcore.Encoder { return &charmEncoder{e.Encoder.Clone()} }
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

func L() *zap.SugaredLogger { return logger }

// Plain methods
func Debug(msg string, args ...any) { zap.S().Debugw(msg, args...) }
func Info(msg string, args ...any)  { zap.S().Infow(msg, args...) }
func Warn(msg string, args ...any)  { zap.S().Warnw(msg, args...) }
func Error(msg string, args ...any) { zap.S().Errorw(msg, args...) }
func Fatal(msg string, args ...any) { zap.S().Fatalw(msg, args...) }
func Print(msg string, args ...any) { zap.S().Infow(msg, args...) }

// Formatted methods
func Debugf(t string, args ...any) { zap.S().Debugf(t, args...) }
func Infof(t string, args ...any)  { zap.S().Infof(t, args...) }
func Warnf(t string, args ...any)  { zap.S().Warnf(t, args...) }
func Errorf(t string, args ...any) { zap.S().Errorf(t, args...) }
func Fatalf(t string, args ...any) { zap.S().Fatalf(t, args...) }
func Printf(t string, args ...any) { zap.S().Infof(t, args...) }

func With(args ...any) *zap.SugaredLogger {
	return zap.S().With(args...)
}
