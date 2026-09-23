# ==============================================================================
# meta.nix - Prelude Module Metadata
#
# Static metadata for fast module discovery. Contains ONLY pure data.
# ==============================================================================
{
  id = "prelude";

  name = "Prelude";

  description = "Devshell UI suite (MOTD, menu/x, docs) — default shell DX layer";

  category = "development";

  version = "1.0.0";

  icon = "terminal";

  homepage = "https://github.com/darkmatter/prelude";

  author = "Stackpanel";

  tags = [
    "prelude"
    "motd"
    "menu"
    "docs"
    "devshell"
    "dx"
  ];

  requires = [ ];

  conflicts = [ ];

  features = {
    files = false;
    scripts = false;
    healthchecks = true;
    packages = true;
    services = false;
    secrets = false;
    tasks = false;
    appModule = false;
  };

  # Delivered transitively via Stackpanel's flakeModules.default / localInputs.
  # Do not list here — that would false-positive missingFlakeInputs for consumers
  # who correctly omit a top-level `prelude` input.
  flakeInputs = [ ];

  priority = 5;
}
