# ==============================================================================
# module.nix - Git Hooks Module Implementation
#
# Git hooks integration using stackpanel app tooling wrappers.
# Consumes stackpanel.appsComputed.<app>.wrappedTooling.* and exposes a
# git-hooks configuration fragment suitable for git-hooks.nix.
#
# Also handles cleanup of stale git hooks that reference garbage-collected
# nix store paths.
#
# Modules can contribute extra linters/formatters via:
#   stackpanel.git-hooks.extraLinters = [ <derivation> ... ];
#   stackpanel.git-hooks.extraFormatters = [ <derivation> ... ];
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;
  gitHooksCfg = cfg.git-hooks or { enable = false; };
  appsComputed = cfg.appsComputed or { };

  # Get tools from app tooling configuration
  allToolsFromApps =
    tools: lib.flatten (lib.mapAttrsToList (_: app: app.wrappedTooling.${tools} or [ ]) appsComputed);

  # Get extra tools contributed by modules (avoids infinite recursion)
  extraLinters = gitHooksCfg.extraLinters or [ ];
  extraFormatters = gitHooksCfg.extraFormatters or [ ];

  # Combine app tools with module-contributed extras
  allLinters = (allToolsFromApps "linters") ++ extraLinters;
  allFormatters = (allToolsFromApps "formatters") ++ extraFormatters;
  allBuildSteps = allToolsFromApps "build-steps";

  toolCommand = tool: {
    entry = "${lib.getExe tool}";
    language = "system";
    pass_filenames = false;
  };

  mkHooks =
    name: tools:
    lib.listToAttrs (
      lib.imap0 (idx: tool: {
        name = "stackpanel-${name}-${toString idx}";
        value = toolCommand tool;
      }) tools
    );

  # Script to clean up stale git hooks that reference missing nix store paths
  cleanStaleGitHooks = ''
    # Clean up stale git hooks that reference garbage-collected nix store paths
    _cleanup_stale_git_hooks() {
      local git_dir hooks_dir
      git_dir="$(git rev-parse --git-dir 2>/dev/null)" || return 0
      hooks_dir="$git_dir/hooks"
      
      [[ -d "$hooks_dir" ]] || return 0
      
      local hook_files=("pre-commit" "pre-push" "commit-msg" "prepare-commit-msg")
      
      for hook in "''${hook_files[@]}"; do
        local hook_path="$hooks_dir/$hook"
        [[ -f "$hook_path" ]] || continue
        
        # Check if hook references a nix store path
        if grep -q '/nix/store/' "$hook_path" 2>/dev/null; then
          # Extract nix store paths and check if they exist
          local store_paths
          store_paths=$(grep -oE '/nix/store/[a-z0-9]+-[^/"]+' "$hook_path" 2>/dev/null | head -5)
          
          local any_missing=false
          while IFS= read -r store_path; do
            [[ -z "$store_path" ]] && continue
            if [[ ! -e "$store_path" ]]; then
              any_missing=true
              break
            fi
          done <<< "$store_paths"
          
          if [[ "$any_missing" == "true" ]]; then
            rm -f "$hook_path"
            echo "Removed stale git hook: $hook (referenced garbage-collected nix store path)"
          fi
        fi
      done
    }
    _cleanup_stale_git_hooks
  '';

in
{
  # ===========================================================================
  # Configuration
  # ===========================================================================
  config = lib.mkMerge [
    # Always clean up stale git hooks on shell entry
    (lib.mkIf cfg.enable {
      stackpanel.devshell.hooks.before = lib.mkBefore [ cleanStaleGitHooks ];
    })

    # Configure git-hooks when enabled
    (lib.mkIf cfg.enable {
      stackpanel.git-hooks = {
        enable = lib.mkDefault true;
        hooks = {
          pre-commit = (mkHooks "formatters" allFormatters) // (mkHooks "linters" allLinters);
          pre-push = mkHooks "build-steps" allBuildSteps;
        };
      };
    })

    # Register module
    (lib.mkIf cfg.enable {
      stackpanel.modules.${meta.id} = {
        enable = true;
        meta = {
          name = meta.name;
          description = meta.description;
          icon = meta.icon;
          category = meta.category;
          author = meta.author;
          version = meta.version;
          homepage = meta.homepage;
        };
        source.type = "builtin";
        features = meta.features;
        tags = meta.tags;
        priority = meta.priority;
      };
    })
  ];
}
