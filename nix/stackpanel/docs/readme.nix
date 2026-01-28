# ==============================================================================
# docs/readme.nix
#
# README generation module. Generates README.md from a template with
# dynamic content injected from the docs and project configuration.
#
# Usage:
#   stackpanel.docs.readme = {
#     enable = true;
#     template = ./README.tmpl.md;  # Optional custom template
#   };
#
# The module reads content from:
#   - The template file (README.tmpl.md by default)
#   - apps/docs/content/docs/index.mdx (vision/intro)
#   - apps/docs/content/docs/quick-start.mdx (quickstart guide)
#
# Generated file is written to README.md in the project root.
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.docs.readme;
  rootCfg = config.stackpanel;

  # Helper to strip MDX frontmatter and imports
  stripMdxHeader = text:
    let
      lines = lib.splitString "\n" text;
      # Find where frontmatter ends (second ---)
      findContentStart = lines: idx: inFrontmatter:
        if idx >= builtins.length lines then idx
        else if builtins.elemAt lines idx == "---" then
          if inFrontmatter then idx + 1  # End of frontmatter
          else findContentStart lines (idx + 1) true  # Start of frontmatter
        else findContentStart lines (idx + 1) inFrontmatter;
      contentStart = findContentStart lines 0 false;
      contentLines = lib.drop contentStart lines;
      # Also strip import statements
      filteredLines = builtins.filter (line:
        !(lib.hasPrefix "import " line) &&
        !(lib.hasPrefix "import{" line)
      ) contentLines;
    in
    lib.concatStringsSep "\n" filteredLines;

  # Strip MDX-specific syntax for plain markdown
  stripMdxSyntax = text:
    let
      # Remove JSX-style components like <Steps>, <Callout>, etc.
      step1 = builtins.replaceStrings
        [ "<Steps>" "</Steps>" "<Step>" "</Step>" "<Callout type=\"info\">" "<Callout>" "</Callout>" "<Tabs items={[" "]>" "</Tabs>" "<Tab value=" "</Tab>" "<br />" "<center>" "</center>" ]
        [ "" "" "" "" "> **Note:** " "> " "" "" "" "" "" "" "" "" "" ]
        text;
      # Remove remaining JSX components (simplified)
      lines = lib.splitString "\n" step1;
      filteredLines = builtins.filter (line:
        !(lib.hasPrefix "<Tab " line) &&
        !(lib.hasPrefix "</Tab>" line) &&
        !(lib.hasPrefix "<Tabs " line) &&
        !(lib.hasPrefix "```files" line)
      ) lines;
    in
    lib.concatStringsSep "\n" filteredLines;

  # Extract a section from markdown by heading
  extractSection = markdown: headingPattern: stopPattern:
    let
      lines = lib.splitString "\n" markdown;
      findStart = lines: idx:
        if idx >= builtins.length lines then null
        else if lib.hasPrefix headingPattern (builtins.elemAt lines idx) then idx
        else findStart lines (idx + 1);
      findEnd = lines: startIdx: idx:
        if idx >= builtins.length lines then idx
        else if idx > startIdx && lib.hasPrefix stopPattern (builtins.elemAt lines idx) then idx
        else findEnd lines startIdx (idx + 1);
      startIdx = findStart lines 0;
    in
    if startIdx == null then ""
    else
      let
        endIdx = findEnd lines startIdx (startIdx + 1);
        sectionLines = lib.sublist startIdx (endIdx - startIdx) lines;
      in
      lib.concatStringsSep "\n" sectionLines;

  # Read and process source docs
  introSource =
    if cfg.introPath != null && builtins.pathExists cfg.introPath
    then stripMdxSyntax (stripMdxHeader (builtins.readFile cfg.introPath))
    else "";

  quickstartSource =
    if cfg.quickstartPath != null && builtins.pathExists cfg.quickstartPath
    then stripMdxSyntax (stripMdxHeader (builtins.readFile cfg.quickstartPath))
    else "";

  # Build the README content
  readmeContent = if cfg.template != null then
    builtins.readFile cfg.template
  else
    ''
      # ${rootCfg.name}

      Powered by [stackpanel](https://github.com/darkmatter/stackpanel).

      ## Getting Started

      ```bash
      nix develop --impure
      ```
    '';

in
{
  options.stackpanel.docs.readme = {
    enable = lib.mkEnableOption "README generation from template";

    template = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to README template file. If null, uses a default minimal template.";
    };

    introPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to introduction/vision MDX file to extract content from.";
    };

    quickstartPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to quickstart MDX file to extract content from.";
    };

    outputPath = lib.mkOption {
      type = lib.types.str;
      default = "README.md";
      description = "Output path for generated README relative to project root.";
    };

    extraContent = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra content to append to the README.";
    };

    # Expose computed values for downstream use
    content = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "The generated README content.";
    };

    introContent = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Extracted intro content from the MDX file.";
    };

    quickstartContent = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Extracted quickstart content from the MDX file.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Expose computed content
    stackpanel.docs.readme.content = readmeContent + cfg.extraContent;
    stackpanel.docs.readme.introContent = introSource;
    stackpanel.docs.readme.quickstartContent = quickstartSource;

    # Generate the README file
    stackpanel.files.entries.${cfg.outputPath} = {
      type = "text";
      text = config.stackpanel.docs.readme.content;
      description = "Generated README";
    };
  };
}
