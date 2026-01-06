package nixeval

import (
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/darkmatter/stackpanel/apps/stackpanel-go/pkg/envvars"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNixEval(t *testing.T) {
	t.Run("evaluates a simple expression", func(t *testing.T) {
		result, err := EvalExpr(t.Context(), "1 + 2")
		require.NoError(t, err)
		assert.Equal(t, "3\n", string(result.Raw))
		root := envvars.StackpanelRoot.Get()
		require.True(t, root != "")
		// should be an absolute path
		require.True(t, strings.HasPrefix(root, "/"))
		// ls the dir
		files, err := os.ReadDir(root)
		require.NoError(t, err)
		for _, file := range files {
			fmt.Println(file.Name())
		}
		// eval config
		r, err := GetConfigWithEval(t.Context(), root)
		require.NoError(t, err)
		fmt.Println(r)
	})
}
