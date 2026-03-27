# ==============================================================================
# ide.nix
#
# IDE integration utilities - pure functions for generating IDE configurations.
# Provides helpers for VS Code/Zed terminal integration, workspace files, and
# development shell loaders.
#
# Features:
#   - VS Code terminal profile configuration for Nix devshells
#   - Zed terminal and task configuration for Nix devshells
#   - Workspace file generation with settings, folders, and extensions
#   - Shell loader scripts that handle Nix availability and project root detection
#   - Support for both devenv and flake-based shells
#
# Usage:
#   let ideLib = import ./ide.nix { inherit pkgs lib; };
#   in ideLib.mkDevshellLoader { shellMode = "devenv"; }
#   in ideLib.mkVscodeSettings { loaderPath = "${workspaceFolder}/.stack/..."; }
#   in ideLib.mkWorkspaceContent { settings = {...}; extensions = []; }
#   in ideLib.mkZedSettings { loaderPath = ".stack/gen/zed/devshell-loader.sh"; }
#   in ideLib.mkZedTasksContent { tasks = [...]; }
# ==============================================================================
{
  pkgs,
  lib,
  ...
}:
{
  # Generate VS Code terminal integration settings
  # Returns an attrset of VS Code settings for terminal integration
  mkVscodeSettings =
    {
      # Path to the devshell loader script (relative to workspace root, with ${workspaceFolder} prefix)
      loaderPath,
    }:
    {
      "terminal.integrated.profiles.osx" = {
        "Devshell" = {
          path = "/bin/bash";
          args = [
            "-c"
            loaderPath
          ];
        };
      };
      "terminal.integrated.profiles.linux" = {
        "Devshell" = {
          path = "/bin/bash";
          args = [
            "-c"
            loaderPath
          ];
        };
      };
      "terminal.integrated.defaultProfile.osx" = "Devshell";
      "terminal.integrated.defaultProfile.linux" = "Devshell";
      "terminal.integrated.shellIntegration.enabled" = true;
    };

  # Generate VS Code workspace file content as an attrset
  # Call builtins.toJSON on the result to get the final content
  mkWorkspaceContent =
    {
      # Merged VS Code settings
      settings,
      # Additional workspace folders beyond the root
      extraFolders ? [ ],
      # Recommended extension IDs
      extensions ? [ ],
      # Relative path from workspace file to project root (default for .stack/gen/ide/vscode/)
      rootPath ? "../../../..",
    }:
    {
      folders = [ { path = rootPath; } ] ++ extraFolders;
      inherit settings;
    }
    // lib.optionalAttrs (extensions != [ ]) {
      extensions.recommendations = extensions;
    };

  # ===========================================================================
  # Zed Editor Integration
  # ===========================================================================

  # Generate Zed terminal integration settings
  # Returns an attrset of Zed settings for terminal integration
  mkZedSettings =
    {
      # Path to the devshell loader script (relative to project root)
      loaderPath,
    }:
    {
      # Configure terminal to use the devshell loader
      load_direnv = "shell_hook";
    };

  # Generate Zed tasks.json content as an attrset
  # Call builtins.toJSON on the result to get the final content
  mkZedTasksContent =
    {
      # List of task definitions
      tasks ? [ ],
      # Shell to use for tasks (defaults to devshell loader)
      loaderPath ? null,
    }:
    let
      # Wrap tasks to run in devshell if loaderPath is provided
      wrapTask =
        task:
        if loaderPath != null then
          task
          // {
            shell = {
              program = "/bin/bash";
              args = [
                "-c"
                "${loaderPath} -c '${task.command} ${lib.concatStringsSep " " (task.args or [ ])}'"
              ];
            };
          }
        else
          task;
    in
    map wrapTask tasks;

  # Generate Zed local settings content (for .zed/settings.json)
  # Merges terminal settings with user settings
  mkZedLocalSettings =
    {
      # Merged Zed settings from user
      settings,
      # Terminal settings (from mkZedSettings)
      terminalSettings ? { },
    }:
    lib.recursiveUpdate terminalSettings settings;

  # Create a shell loader script for IDEs like VS Code
  # Returns either a derivation (asPackage=true) or script content string (asPackage=false)
  mkDevshellLoader =
    {
      # Shell mode: "devenv" uses devenv shell, "flake" uses nix develop
      shellMode ? "flake",
      # Custom nix command to run the devshell (overrides shellMode if set)
      exec ? null,
      # Enable VS Code anti-recursion protection
      vscode ? true,
      # Enable Zed anti-recursion protection
      zed ? true,
      # Return as package (derivation) or raw script content
      asPackage ? true,
    }:
    let
      # Determine exec command based on shellMode
      # Helper function to compute shell hash (same as in core/default.nix)
      shellHashFunc = ''
        _sp_compute_shell_hash() {
          local files=(
            "$ROOT/flake.nix"
            "$ROOT/flake.lock"
            "$ROOT/.stack/config.nix"
            "$ROOT/devenv.nix"
            "$ROOT/devenv.yaml"
          )
          local hash_input=""
          for f in "''${files[@]}"; do
            if [[ -f "$f" ]]; then
              hash_input+="$(cat "$f" 2>/dev/null)"
            fi
          done
          echo -n "$hash_input" | md5sum | cut -d' ' -f1
        }
      '';

      # Helper to check if cached env is fresh
      cacheCheckFunc = ''
        _sp_cache_is_fresh() {
          local cache_file="$1"
          [[ -f "$cache_file" ]] || return 1

          # Extract hash from cache header (line 3: "# Shell hash: <hash>")
          local cached_hash
          cached_hash=$(sed -n '3s/^# Shell hash: //p' "$cache_file" 2>/dev/null)
          [[ -n "$cached_hash" ]] || return 1

          # Compare with current hash
          local current_hash
          current_hash=$(_sp_compute_shell_hash)
          [[ "$cached_hash" == "$current_hash" ]]
        }
      '';

      execCommand =
        if exec != null then
          exec
        else if shellMode == "stackpanel" then
          # Use cached nix-print-dev-env.sh for fast loading, warn if stale
          # Fall back to devshell script or nix develop --impure if no cache
          ''
            ${shellHashFunc}
            ${cacheCheckFunc}

            _sp_cached_env="$ROOT/.stack/gen/nix-print-dev-env.sh"
            if [[ -f "$_sp_cached_env" ]]; then
              if ! _sp_cache_is_fresh "$_sp_cached_env"; then
                echo "⚠️  devshell: cached env is stale (run 'nix develop --impure' to refresh)" >&2
              fi
              . "$_sp_cached_env"
            else
              DEV_SCRIPT="$ROOT/devshell"

              if [[ -x "$DEV_SCRIPT" ]]; then
                exec "$DEV_SCRIPT"
              fi

              # Fallback: enter the devshell directly (runs hooks that materialize ./devshell)
              exec nix develop --impure
            fi
          ''
        else if shellMode == "flake" then
          # Use cached nix-print-dev-env.sh for fast loading, warn if stale
          ''
            ${shellHashFunc}
            ${cacheCheckFunc}

            _sp_cached_env="$ROOT/.stack/gen/nix-print-dev-env.sh"
            if [[ -f "$_sp_cached_env" ]]; then
              if ! _sp_cache_is_fresh "$_sp_cached_env"; then
                echo "⚠️  devshell: cached env is stale (run 'nix develop --impure' to refresh)" >&2
              fi
              . "$_sp_cached_env"
            else
              . <(nix print-dev-env --impure)
            fi
          ''
        else
          ". <(devenv print-dev-env --impure)";

      # Determine which file to look for when finding project root
      lookupFile = if shellMode == "flake" then "flake.nix" else ".git";

      mkAntiRecursion =
        which:
        if which == "vscode" then
          ''
            # Avoid recursion if VS Code reuses this profile inside itself
            if [[ "''${DEVENV_VSCODE_SHELL:-}" == "1" ]]; then
              # If we're already inside, just start a login shell.
              exec "''${SHELL:-/bin/bash}" -l
            fi
            export DEVENV_VSCODE_SHELL=1
          ''
        else if which == "zed" then
          ''
            if [[ -n "''${ZED_TERM:-}" ]]; then
              # If we're already inside, just start a login shell.
              exec "''${SHELL:-/bin/bash}" -l
            fi
          ''
        else
          "";

      anti-recursion-script =
        if vscode then
          mkAntiRecursion "vscode"
        else if zed then
          mkAntiRecursion "zed"
        else
          "";

      script = lib.concatStringsSep "\n" [
        "#!/usr/bin/env bash"
        "# syntax: bash"
        "#"
        "# Development shell loader"
        "#"
        "# Loader for IDEs like VS Code to start a shell inside a Nix-based development environment."
        "# Handles common edge cases like Nix not being in PATH yet."
        "#"
        "# Shell mode: ${shellMode}"
        "# Lookup file: ${lookupFile}"
        "#"
        ""
        # "export DIRENV_DISABLE=1"
        ""
        "# --- small helpers"
        ''die() { printf "devshell: %s\\n" "$*" >&2; exit 1; }''
        ""
        anti-recursion-script
        "# Ensure nix is available"
        "if ! command -v nix >/dev/null 2>&1; then"
        "  if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then"
        "    # shellcheck disable=SC1091"
        "    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
        ''elif [[ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then''
        "    # shellcheck disable=SC1091"
        ''. "$HOME/.nix-profile/etc/profile.d/nix.sh"''
        "  elif [[ -e /etc/profile.d/nix.sh ]]; then"
        "    # shellcheck disable=SC1091"
        "    . /etc/profile.d/nix.sh"
        "  fi"
        "fi"
        ''command -v nix >/dev/null 2>&1 || die "nix not found, install it: https://install.determinate.systems"''
        ""
        "# Find the right project root"
        "find_root() {"
        ''if [[ -n "''${STACKPANEL_ROOT:-}" ]]; then''
        "    printf \"%s\\\\n\" \"$STACKPANEL_ROOT\""
        "    return 0"
        "  fi"
        "  # Prefer git root if available"
        "  if command -v git >/dev/null 2>&1; then"
        "    local gr"
        ''gr="$(git rev-parse --show-toplevel 2>/dev/null || true)"''
        ''if [[ -n "$gr" && -e "$gr/${lookupFile}" ]]; then''
        ''printf "%s\\n" "$gr"''
        "      return 0"
        "    fi"
        "  fi"
        ""
        "  # Walk up from current dir"
        ''local d="$PWD"''
        ''while [[ "$d" != "/" ]]; do''
        ''if [[ -e "$d/${lookupFile}" ]]; then''
        ''printf "%s\\n" "$d"''
        "      return 0"
        "    fi"
        ''d="$(dirname "$d")"''
        "  done"
        ""
        ''die "couldn't find ${lookupFile} (open VS Code at the repo root)"''
        "}"
        ""
        ''ROOT="$(find_root)"''
        ''cd "$ROOT"''
        ""
        "${execCommand}"
      ];
    in
    if asPackage then pkgs.writeShellScriptBin "devshell-loader" script else script;

  # Generate just the script content (for use with stackpanel.files)
  mkDevshellLoaderScript = args: (args // { asPackage = false; });
}
