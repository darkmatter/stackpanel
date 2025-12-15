# File generation system
# Standalone module - no flake-parts dependency
#
# Exposes: `nix run .#generate` and `nix run .#generate-diff`
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.stackpanel;
  files = cfg.files;
  header = cfg.generatedHeader;
  root = cfg.projectRoot;

  # Add header to text content
  withHeader = ext: content: let
    commentStyle = {
      nix = "#";
      yml = "#";
      yaml = "#";
      sh = "#";
      toml = "#";
      py = "#";
      json = null; # JSON doesn't support comments
      ts = "//";
      js = "//";
      tsx = "//";
      jsx = "//";
      go = "//";
      md = "<!--";
    };
    style = commentStyle.${ext} or null; # No header for unknown types
  in
    if style == null
    then content
    else if style == "<!--"
    then ''
      <!-- ${header} -->
      ${content}''
    else ''
      ${style} ${header}
      ${content}'';

  getExt = path: let parts = lib.splitString "." path; in lib.last parts;

  # Only generate if there are files
  hasFiles = files != {};
in {
  config = lib.mkIf cfg.enable {
    stackpanel.packages = {
      # nix run .#generate
      generate =
        pkgs.writeShellScriptBin "stackpanel-generate"
        (
          if hasFiles
          then ''
            set -euo pipefail
            cd "${root}"
            echo "Generating stackpanel files..."
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (path: content: let
                ext = getExt path;
                finalContent =
                  if builtins.isPath content
                  then builtins.readFile content
                  else withHeader ext content;
              in ''
                              mkdir -p "$(dirname "${path}")"
                              cat > "${path}" << 'STACKPANEL_EOF'
                ${finalContent}
                STACKPANEL_EOF
                              echo "  ✓ ${path}"
              '')
              files)}
            echo "Done! Generated ${
              toString (lib.length (lib.attrNames files))
            } files."
          ''
          else ''
            echo "No files configured in stackpanel.files"
            echo "Add files in your flake.nix perSystem config"
          ''
        );

      # nix run .#generate-diff (dry run / preview)
      generate-diff =
        pkgs.writeShellScriptBin "stackpanel-generate-diff"
        (
          if hasFiles
          then ''
            echo "=== stackpanel managed files (${
              toString (lib.length (lib.attrNames files))
            }) ==="
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (path: content: let
                ext = getExt path;
                finalContent =
                  if builtins.isPath content
                  then builtins.readFile content
                  else withHeader ext content;
              in ''
                              echo ""
                              echo "─── ${path} ───"
                              cat << 'STACKPANEL_EOF'
                ${finalContent}
                STACKPANEL_EOF
              '')
              files)}
          ''
          else ''
            echo "No files configured in stackpanel.files"
          ''
        );
    };
  };
}
