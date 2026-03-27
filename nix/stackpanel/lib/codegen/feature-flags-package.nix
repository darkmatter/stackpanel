# ==============================================================================
# feature-flags-package.nix
#
# Generates the packages/gen/featureflags structure from the built-in feature-flag
# definitions. The generated package exposes shared feature-flag logic so it can
# be reused by multiple apps.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel;

  # Module options used by callers.
  featureFlagsCfg = cfg.feature-flags or { };
  featureFlagsOutputDir = featureFlagsCfg.output-dir or "packages/gen/featureflags";
  packageName = featureFlagsCfg.package-name or "@gen/featureflags";

  # Stable defaults used when no overrides are configured.
  defaultDefinitions = [
    {
      key = "studio.overview.layout";
      jsKey = "overviewLayout";
      kind = "variant";
      label = "Overview layout";
      description = "Select between classic and compact studio overview layouts for experiments.";
      defaultValue = "classic";
      rollout = 100;
      variants = [
        "classic"
        "compact"
      ];
    }
    {
      key = "studio.overview.pulse-banner";
      jsKey = "overviewPulseBanner";
      kind = "boolean";
      label = "Pulse banner on overview";
      description = "Show the experimental pulse indicator in the overview panel.";
      defaultValue = false;
      rollout = 0;
    }
  ];

  # Optional override hook. Keep stable if unset.
  definitions =
    if (featureFlagsCfg.definitions or null) != null then
      featureFlagsCfg.definitions
    else
      defaultDefinitions;
  normalizedDefinitions = map (flag: builtins.removeAttrs flag [ "jsKey" ]) definitions;

  packageDir = featureFlagsOutputDir;
  srcDir = "${packageDir}/src";

  # ---------------------------------------------------------------------------
  # Template loading
  # ---------------------------------------------------------------------------
  templateDir = ./templates/feature-flags;

  templates = {
    featureFlags = builtins.readFile "${templateDir}/feature-flags.tsx.tmpl";
    index = builtins.readFile "${templateDir}/index.ts";
    packageJson = builtins.readFile "${templateDir}/package.json.tmpl";
    tsconfig = builtins.readFile "${templateDir}/tsconfig.json";
    readme = builtins.readFile "${templateDir}/README.tmpl.md";
  };

  # Build stable JSON blocks for template substitution.
  sanitizedFlagKeyName = key: lib.replaceStrings [ "." "-" ] [ "_" "_" ] key;

  featureFlagKeys = builtins.listToAttrs (
    map (flag: {
      name = flag.jsKey or (sanitizedFlagKeyName flag.key);
      value = flag.key;
    }) definitions
  );

  generatedFiles = {
    "${packageDir}/package.json" =
      builtins.replaceStrings
        [
          "{{PACKAGE_NAME}}"
        ]
        [
          packageName
        ]
        templates.packageJson;

    "${packageDir}/src/feature-flags.tsx" =
      builtins.replaceStrings
        [
          "{{FEATURE_FLAG_DEFINITIONS}}"
          "{{FEATURE_FLAG_KEYS}}"
        ]
        [
          (builtins.toJSON normalizedDefinitions)
          (builtins.toJSON featureFlagKeys)
        ]
        templates.featureFlags;

    "${packageDir}/src/index.ts" = templates.index;
    "${packageDir}/tsconfig.json" = templates.tsconfig;

    "${packageDir}/README.md" =
      builtins.replaceStrings
        [
          "{{PACKAGE_NAME}}"
        ]
        [
          packageName
        ]
        templates.readme;
  };

  fileEntries = lib.mapAttrs (path: content: {
    type = "text";
    text = content;
    source = "codegen/feature-flags-package.nix";
    description = "Auto-generated feature-flags package file";
  }) generatedFiles;
in
{
  inherit
    generatedFiles
    fileEntries
    definitions
    featureFlagKeys
    ;

  enabled = cfg.enable && (definitions != [ ]);
}
