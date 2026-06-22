package nixeval_test

import (
	"testing"

	"github.com/darkmatter/stackpanel/stackpanel-go/pkg/nixeval"
	"github.com/stretchr/testify/require"
)

func TestInitFilesFlakeAttrUsesNamedTemplate(t *testing.T) {
	t.Parallel()

	got, err := nixeval.InitFilesFlakeAttr("github:darkmatter/stackpanel", "minimal")
	require.NoError(t, err)
	require.Equal(t, "github:darkmatter/stackpanel#lib.initTemplates.minimal", got)
}

func TestInitFilesFlakeAttrDefaultsTemplate(t *testing.T) {
	t.Parallel()

	got, err := nixeval.InitFilesFlakeAttr("github:darkmatter/stackpanel", "")
	require.NoError(t, err)
	require.Equal(t, "github:darkmatter/stackpanel#lib.initTemplates.default", got)
}

func TestInitFilesFlakeAttrRejectsInvalidTemplate(t *testing.T) {
	t.Parallel()

	_, err := nixeval.InitFilesFlakeAttr("github:darkmatter/stackpanel", "../bad")
	require.Error(t, err)
}
