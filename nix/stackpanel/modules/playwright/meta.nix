# ==============================================================================
# meta.nix - Playwright Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  id = "playwright";
  name = "Playwright";
  description = "Playwright end-to-end testing: config, e2e workflow, test:e2e script";
  category = "development";
  version = "1.0.0";
  icon = "flask-conical";
  homepage = "https://playwright.dev";
  author = "Stackpanel";
  tags = [
    "playwright"
    "e2e"
    "testing"
    "browser"
  ];
  requires = [ ];
  conflicts = [ ];
  features = {
    files = true;
    scripts = false;
    healthchecks = true;
    packages = false;
    services = false;
    secrets = false;
    tasks = false;
    appModule = false;
  };
  flakeInputs = [ ];
  priority = 80;
}
