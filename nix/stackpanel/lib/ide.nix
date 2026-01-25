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
#   in ideLib.mkVscodeSettings { loaderPath = "${workspaceFolder}/.stackpanel/..."; }
#   in ideLib.mkWorkspaceContent { settings = {...}; extensions = []; }
#   in ideLib.mkZedSettings { loaderPath = ".stackpanel/gen/zed/devshell-loader.sh"; }
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
      # Relative path from workspace file to project root (default for .stackpanel/gen/ide/vscode/)
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
      terminal = {
        shell = {
          program = "/bin/bash";
          args = [
            "-c"
            loaderPath
          ];
        };
      };
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
              with_arguments = {
                program = "/bin/bash";
                args = [
                  "-c"
                  "${loaderPath} -c '${task.command} ${lib.concatStringsSep " " (task.args or [ ])}'"
                ];
                title_override = "devshell";
              };
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
      # Return as package (derivation) or raw script content
      asPackage ? true,
    }:
    let
      # Determine exec command based on shellMode
      execCommand =
        if exec != null then
          exec
        else if shellMode == "stackpanel" then
          ''
            DEV_SCRIPT="$ROOT/devshell"

            if [[ -x "$DEV_SCRIPT" ]]; then
              exec "$DEV_SCRIPT"
            fi

            # Fallback: enter the devshell directly (runs hooks that materialize ./devshell)
            exec nix develop --impure
          ''
        else if shellMode == "flake" then
          ". <(nix print-dev-env --impure)"
        else
          ". <(devenv print-dev-env --impure)";

      # Determine which file to look for when finding project root
      lookupFile = if shellMode == "flake" then "flake.nix" else "devenv.yaml";

      vscode-anti-recursion =
        if vscode then
          ''
            # Avoid recursion if VS Code reuses this profile inside itself
            if [[ "''${DEVENV_VSCODE_SHELL:-}" == "1" ]]; then
              # If we're already inside, just start a login shell.
              exec "''${SHELL:-/bin/bash}" -l
            fi
            export DEVENV_VSCODE_SHELL=1
          ''
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
        vscode-anti-recursion
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
        ''if [[ -n "$gr" && -f "$gr/${lookupFile}" ]]; then''
        ''printf "%s\\n" "$gr"''
        "      return 0"
        "    fi"
        "  fi"
        ""
        "  # Walk up from current dir"
        ''local d="$PWD"''
        ''while [[ "$d" != "/" ]]; do''
        ''if [[ -f "$d/${lookupFile}" ]]; then''
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
