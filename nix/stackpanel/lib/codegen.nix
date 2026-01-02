# ==============================================================================
# codegen.nix
#
# File generation system for materializing configuration files into a project.
# This is a standalone module with no flake-parts dependency.
#
# Features:
#   - Generates files with appropriate comment headers based on file extension
#   - Supports multiple file types (nix, yaml, sh, toml, ts, js, go, md, etc.)
#   - Creates executable files with proper chmod
#   - Provides both generate and generate-diff commands
#
# Exposes: `nix run .#generate` and `nix run .#generate-diff`
#
# Usage:
#   stackpanel.files = { "path/to/file.yaml" = "content"; };
#   stackpanel.executableFiles = [ "scripts/run.sh" ];
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.stackpanel;
  files = cfg.files;
  executableFiles = cfg.executableFiles;
  header = cfg.generatedHeader;
  root = cfg.projectRoot;

  # Comment styles by file extension
  commentStyles = {
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

  # Extract file extension from path
  getExt = path:
    lib.last (lib.splitString "." path);

  # Add header comment to content based on file extension
  withHeader = ext: content: let
    style = commentStyles.${ext} or null;
  in
    if style == null then content
    else if style == "<!--" then "<!-- ${header} -->\n${content}"
    else "${style} ${header}\n${content}";

  # Process a single file entry into its final content
  processFile = path: content: let
    ext = getExt path;
  in
    if builtins.isPath content
    then builtins.readFile content
    else withHeader ext content;

  # Pre-process all files into a list of { path, content } attrs
  processedFiles = lib.mapAttrsToList
    (path: content: {
      inherit path;
      content = processFile path content;
    })
    files;

  hasFiles = files != {};
  fileCount = toString (lib.length (lib.attrNames files));
  hasExecutables = executableFiles != [];

  # Generate chmod command for executable files
  mkChmodCommand = path: ''chmod +x "${path}" && echo "  ⚡ ${path} (executable)"'';

  # Generate shell command for writing a single file
  mkWriteCommand = file: lib.concatStringsSep "\n" [
    ''mkdir -p "$(dirname "${file.path}")"''
    "cat > \"${file.path}\" << 'STACKPANEL_EOF'"
    file.content
    "STACKPANEL_EOF"
    ''echo "  ✓ ${file.path}"''
  ];

  # Generate shell command for displaying a single file
  mkDisplayCommand = file: lib.concatStringsSep "\n" [
    ''echo ""''
    ''echo "─── ${file.path} ───"''
    "cat << 'STACKPANEL_EOF'"
    file.content
    "STACKPANEL_EOF"
  ];

  # Script bodies
  generateScript = lib.concatStringsSep "\n" ([
    "set -euo pipefail"
    ''cd "${root}"''
    ''echo "Generating stackpanel files..."''
    (lib.concatMapStringsSep "\n" mkWriteCommand processedFiles)
  ] ++ lib.optionals hasExecutables [
    ''echo ""''
    ''echo "Making files executable..."''
    (lib.concatMapStringsSep "\n" mkChmodCommand executableFiles)
  ] ++ [
    ''echo ""''
    ''echo "Done! Generated ${fileCount} files."''
  ]);

  generateDiffScript = lib.concatStringsSep "\n" [
    ''echo "=== stackpanel managed files (${fileCount}) ==="''
    (lib.concatMapStringsSep "\n" mkDisplayCommand processedFiles)
  ];

  noFilesMessage = ''echo "No files configured in stackpanel.files"'';

  noFilesScript = lib.concatStringsSep "\n" [
    noFilesMessage
    ''echo "Add files in your flake.nix perSystem config"''
  ];

in {
  config = lib.mkIf cfg.enable {
    # Add generation scripts to the devshell packages
    stackpanel.devshell.packages = [
      (pkgs.writeShellScriptBin "stackpanel-generate"
        (if hasFiles then generateScript else noFilesScript))
      (pkgs.writeShellScriptBin "stackpanel-generate-diff"
        (if hasFiles then generateDiffScript else noFilesMessage))
    ];
  };
}
