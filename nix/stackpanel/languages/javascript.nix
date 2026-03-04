# ==============================================================================
# javascript.nix - JavaScript/Node.js Language Toolchain
#
# Sets up Node.js, package managers (bun, npm, pnpm, yarn), and auto-install
# hooks. This replaces devenv's languages.javascript module.
#
# The auto-install feature (e.g., bun.install.enable) runs the package manager's
# install command on shell entry, but only when the lockfile has changed since
# the last install. This avoids redundant installs on every shell entry.
#
# Usage in .stack/config.nix:
#   languages.javascript = {
#     enable = true;
#     bun.enable = true;
#     bun.install.enable = true;
#   };
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.languages.javascript;
  rootDir = if config.stackpanel.root != null then config.stackpanel.root else ".";

  nodeModulesPath = "${
    lib.optionalString (cfg.directory != rootDir) ''"${cfg.directory}/"''
  }node_modules";

  # ---------------------------------------------------------------------------
  # Auto-install scripts
  # Each checks a hash of the lockfile to avoid redundant installs.
  # ---------------------------------------------------------------------------
  initBunScript = pkgs.writeShellScript "stackpanel-bun-install" ''
    _stackpanel_bun_install() {
      local lock_file
      if [ -f ${lib.optionalString (cfg.directory != rootDir) ''"${cfg.directory}/"''}bun.lock ]; then
        lock_file="${lib.optionalString (cfg.directory != rootDir) ''"${cfg.directory}/"''}bun.lock"
      elif [ -f ${
        lib.optionalString (cfg.directory != rootDir) ''"${cfg.directory}/"''
      }bun.lockb ]; then
        lock_file="${lib.optionalString (cfg.directory != rootDir) ''"${cfg.directory}/"''}bun.lockb"
      else
        echo "No bun lockfile found. Run 'bun install' to create one." >&2
        return 0
      fi

      local ACTUAL_CHECKSUM="${cfg.bun.package.version}:$(${pkgs.nix}/bin/nix-hash --type sha256 "$lock_file")"
      local CHECKSUM_FILE="${nodeModulesPath}/bun.lock.checksum"

      local EXPECTED_CHECKSUM=""
      if [ -f "$CHECKSUM_FILE" ]; then
        read -r EXPECTED_CHECKSUM < "$CHECKSUM_FILE"
      fi

      if [ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
        echo "Installing bun dependencies..." >&2
        if ${cfg.bun.package}/bin/bun install ${
          lib.optionalString (cfg.directory != rootDir) "--cwd ${cfg.directory}"
        }; then
          echo "$ACTUAL_CHECKSUM" > "$CHECKSUM_FILE"
        else
          echo "bun install failed. Run 'bun install' manually." >&2
        fi
      fi
    }

    if [ ! -f ${
      lib.optionalString (cfg.directory != rootDir) ''"${cfg.directory}/"''
    }package.json ]; then
      echo "No package.json found. Run 'bun init' to create one." >&2
    else
      _stackpanel_bun_install
    fi
  '';

  initNpmScript = pkgs.writeShellScript "stackpanel-npm-install" ''
    _stackpanel_npm_install() {
      local ACTUAL_CHECKSUM="${cfg.npm.package.version}:$(${pkgs.nix}/bin/nix-hash --type sha256 ${
        lib.optionalString (cfg.directory != rootDir) ''"${cfg.directory}/"''
      }package-lock.json)"
      local CHECKSUM_FILE="${nodeModulesPath}/package-lock.json.checksum"

      local EXPECTED_CHECKSUM=""
      if [ -f "$CHECKSUM_FILE" ]; then
        read -r EXPECTED_CHECKSUM < "$CHECKSUM_FILE"
      fi

      if [ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
        echo "Installing npm dependencies..." >&2
        if ${cfg.npm.package}/bin/npm install ${
          lib.optionalString (cfg.directory != rootDir) "--prefix ${cfg.directory}"
        }; then
          echo "$ACTUAL_CHECKSUM" > "$CHECKSUM_FILE"
        else
          echo "npm install failed. Run 'npm install' manually." >&2
        fi
      fi
    }

    if [ ! -f ${
      lib.optionalString (cfg.directory != rootDir) ''"${cfg.directory}/"''
    }package.json ]; then
      echo "No package.json found. Run 'npm init' to create one." >&2
    else
      _stackpanel_npm_install
    fi
  '';
in
{
  options.stackpanel.languages.javascript = {
    enable = lib.mkEnableOption "JavaScript/Node.js development toolchain";

    directory = lib.mkOption {
      type = lib.types.str;
      default = if config.stackpanel.root != null then config.stackpanel.root else ".";
      defaultText = "config.stackpanel.root";
      description = "Project root for JavaScript tooling. Defaults to the repo root.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nodejs-slim;
      defaultText = lib.literalExpression "pkgs.nodejs-slim";
      description = "The Node.js package to use.";
    };

    corepack.enable = lib.mkEnableOption "Node.js Corepack (npm, pnpm, yarn wrappers)";

    npm = {
      enable = lib.mkEnableOption "npm";
      package = lib.mkOption {
        type = lib.types.package;
        default = cfg.package.override { enableNpm = true; };
        defaultText = lib.literalExpression "cfg.package.override { enableNpm = true; }";
        description = "The Node.js package with npm enabled.";
      };
      install.enable = lib.mkEnableOption "auto-run npm install on shell entry";
    };

    pnpm = {
      enable = lib.mkEnableOption "pnpm";
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.nodePackages.pnpm;
        defaultText = lib.literalExpression "pkgs.nodePackages.pnpm";
        description = "The pnpm package to use.";
      };
    };

    yarn = {
      enable = lib.mkEnableOption "yarn";
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.yarn.override { nodejs = cfg.package; };
        defaultText = lib.literalExpression "pkgs.yarn";
        description = "The yarn package to use.";
      };
    };

    bun = {
      enable = lib.mkEnableOption "bun runtime";
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.bun;
        defaultText = lib.literalExpression "pkgs.bun";
        description = "The bun package to use.";
      };
      install.enable = lib.mkEnableOption "auto-run bun install on shell entry";
    };

    lsp = {
      enable = lib.mkEnableOption "TypeScript language server" // {
        default = true;
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.typescript-language-server;
        defaultText = lib.literalExpression "pkgs.typescript-language-server";
        description = "The TypeScript/JavaScript language server package to use.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.devshell.packages =
      # Node: use npm-enabled variant if npm is enabled, otherwise slim
      lib.optional (!cfg.npm.enable) cfg.package
      ++ lib.optional cfg.npm.enable cfg.npm.package
      ++ lib.optional cfg.pnpm.enable cfg.pnpm.package
      ++ lib.optional cfg.yarn.enable (cfg.yarn.package.override { nodejs = cfg.package; })
      ++ lib.optional cfg.bun.enable cfg.bun.package
      ++ lib.optional cfg.corepack.enable (
        pkgs.runCommand "corepack-enable" { } ''
          mkdir -p $out/bin
          ${cfg.package}/bin/corepack enable --install-directory $out/bin
        ''
      )
      ++ lib.optional cfg.lsp.enable cfg.lsp.package;

    stackpanel.devshell.hooks.main =
      # Auto-install hooks
      (lib.optional cfg.bun.install.enable ''
        # JavaScript toolchain: auto-install bun dependencies
        source ${initBunScript}
      '')
      ++ (lib.optional cfg.npm.install.enable ''
        # JavaScript toolchain: auto-install npm dependencies
        source ${initNpmScript}
      '')
      ++ [
        ''
          # JavaScript toolchain: add node_modules/.bin to PATH
          export PATH="$STACKPANEL_ROOT/${nodeModulesPath}/.bin:$PATH"
        ''
      ];

    stackpanel.motd.features = [
      "Node.js"
    ]
    ++ lib.optional cfg.bun.enable "Bun"
    ++ lib.optional cfg.npm.enable "npm"
    ++ lib.optional cfg.pnpm.enable "pnpm"
    ++ lib.optional cfg.yarn.enable "yarn";
  };
}
