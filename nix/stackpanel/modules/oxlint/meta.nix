# ==============================================================================
# meta.nix - OxLint Module Metadata
#
# Static metadata for fast discovery. No imports, no lib calls.
# ==============================================================================
{
  id = "oxlint";
  name = "OxLint";
  description = "Blazing fast JavaScript/TypeScript linter written in Rust";
  category = "development";
  version = "1.0.0";
  icon = "search-code";
  homepage = "https://oxc.rs";
  author = "Stackpanel";

  tags = [
    "linting"
    "javascript"
    "typescript"
    "react"
    "oxc"
    "rust"
  ];

  requires = [ ];
  conflicts = [ ];

  features = {
    files = true;
    scripts = true;
    healthchecks = true;
    packages = true;
    services = false;
    secrets = false;
    tasks = false;
    appModule = true;
  };

  priority = 50;
}
