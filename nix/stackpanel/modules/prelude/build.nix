# ==============================================================================
# build.nix — Build packages.prelude from façade (prelude.* fragment) via prelude.lib
#
# Used from the flake integration perSystem so project name, status lights,
# env chips, and commands all come from the Stackpanel eval. Kept while we
# verify Prelude's own package generators honor late perSystem prelude merges;
# both paths share facade.nix as the single mapper.
# ==============================================================================
{
  pkgs,
  lib,
  preludeLib,
  facade,
  # Optional: Go 1.26+ toolchain (Prelude go.mod requires >= 1.26).
  buildGoModule ? pkgs.buildGoModule,
}:
let
  deps = {
    inherit (pkgs)
      lib
      writeText
      writeShellApplication
      symlinkJoin
      runCommand
      nixosOptionsDoc
      figlet
      ;
    inherit buildGoModule;
  };

  theme = facade.theme or "minted";
  project = facade.project or "project";
  commands = facade.commands or { };
  groups =
    facade.sort.groups or [
      "develop"
      "database"
      "deploy"
      "ops"
    ];
  motd = facade.motd or { };

  shared = {
    inherit theme project;
    palette = facade.palette or { };
    colorProfile = facade.colorProfile or "auto";
  };

  motdConfig = shared // {
    commandCatalog = commands;
    commandGroupOrder = groups;
    shortcuts = [ ];
    enable = motd.enable or true;
    description =
      motd.description or {
        text = "";
      };
    header =
      motd.header or {
        tagline = {
          text = "${project} devshell";
          subtitle = "your environment is ready";
        };
        status = { };
        statusHint = {
          layout = "inline";
          links = [ ];
        };
        background = false;
      };
    env = motd.env or [ ];
    recipes = motd.recipes or { };
    links = motd.links or [ ];
    title =
      motd.title or {
        text = null;
        align = "center";
        style = "spine";
      };
    clearScreen = motd.clearScreen or true;
    background = motd.background or false;
    windowBackground = motd.windowBackground or true;
    align = motd.align or "center";
    gettingStarted =
      motd.gettingStarted or {
        heading = "Getting Started";
        commandsLabel = "commands";
        examplesLabel = "examples";
        commandNote = "prefix with `x` if a command is shadowed";
      };
  };

  menuEnable = facade.menu.enable or true;
  menuCfg = facade.menu or { };
  menuConfig = lib.recursiveUpdate (
    shared
    // {
      inherit commands;
      groupOrder = groups;
      placeholder = "type to filter commands…";
      height = 20;
      execute = true;
      width = "full";
      maxWidth = 80;
    }
  ) (builtins.removeAttrs menuCfg [ "enable" ]);

  motdPkg = preludeLib.mkMotd deps motdConfig;
  menuPkg = if menuEnable then preludeLib.mkMenu deps menuConfig else null;

  docsEnable = (facade.docs.pages or [ ]) != [ ];
  docsPages = lib.filter (p: p ? text && lib.hasSuffix ".md" (toString p.text)) (
    facade.docs.pages or [ ]
  );
  docsPkg =
    if docsEnable && docsPages != [ ] then
      preludeLib.mkDocs deps (
        shared
        // {
          pages = docsPages;
          rootReadme = null;
          nixosOptions = {
            options = { };
          };
        }
      )
    else
      null;

  paths = [
    motdPkg
  ]
  ++ lib.optional (menuPkg != null) menuPkg
  ++ lib.optional (docsPkg != null) docsPkg;
in
{
  motd = motdPkg;
  menu = menuPkg;
  docs = docsPkg;
  prelude = pkgs.symlinkJoin {
    name = "prelude";
    inherit paths;
    meta = {
      description = "Stackpanel-façade Prelude (motd, menu/x, docs)";
      mainProgram = "motd";
    };
  };
}
