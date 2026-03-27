package server

import "embed"

// templatesFS embeds HTML templates (currently just pair.html for the browser
// pairing popup) into the binary so the agent has zero runtime file dependencies.
//
//go:embed templates/*.html
var templatesFS embed.FS
