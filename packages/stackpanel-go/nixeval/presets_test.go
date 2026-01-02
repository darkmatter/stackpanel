package nixeval_test

import (
	"context"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/darkmatter/stackpanel/packages/stackpanel-go/nixeval"
	cp "github.com/otiai10/copy"
	"github.com/stretchr/testify/require"
)

func TestEvalExpr(t *testing.T) {
	_, filename, _, ok := runtime.Caller(0)
	require.True(t, ok, "unable to determine test file path")
	baseTemplatePath := filepath.Join(filepath.Dir(filename), "testdata")
	t.Setenv("STACKPANEL_ROOT", "")
	tests := []struct {
		name         string
		templatePath string
		nixExpr      string
		wantJSON     string
		wantErr      bool
	}{
		{
			name:         "users preset returns data",
			templatePath: filepath.Join(baseTemplatePath, "users"),
			nixExpr:      nixeval.UsersPreset,
			wantJSON:     `{"alice":{"github":"alicehub","name":"Alice Example","public-keys":["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey"],"secrets-allowed-environments":["dev","production"]}}`,
		},
		{
			name:         "users preset missing file returns empty object",
			templatePath: filepath.Join(baseTemplatePath, "minimal"),
			nixExpr:      nixeval.UsersPreset,
			wantJSON:     `{}`,
		},
		{
			name:         "invalid expression returns error",
			templatePath: filepath.Join(baseTemplatePath, "minimal"),
			nixExpr:      `builtins.throw "boom"`,
			wantErr:      true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dest := t.TempDir()
			if tt.templatePath != "" {
				// use templates to create demo projects to test against
				err := cp.Copy(tt.templatePath, dest)
				require.NoError(t, err)
			}
			t.Setenv("STACKPANEL_ROOT", dest)
			got, gotErr := nixeval.EvalExpr(context.Background(), tt.nixExpr)
			if gotErr != nil {
				if !tt.wantErr {
					t.Errorf("EvalExpr() failed: %v", gotErr)
				}
				return
			}
			if tt.wantErr {
				t.Fatal("EvalExpr() succeeded unexpectedly")
			}
			require.JSONEq(t, tt.wantJSON, string(got.Raw))
		})
	}
}
