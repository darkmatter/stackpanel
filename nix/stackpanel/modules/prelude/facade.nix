# ==============================================================================
# facade.nix — Map stackpanel.motd.* (+ identity) into a prelude.* config fragment
#
# Pure function. Returns an attrset assignable to flake-parts `config.prelude`
# (and consumable by build.nix). Does NOT dump Prelude's ACME demo catalogue.
# ==============================================================================
{ lib }:
{
  name,
  github ? "",
  motd,
  preludeCfg,
  projectRoot ? null,
}:
let
  inherit (lib)
    concatStrings
    concatStringsSep
    filter
    hasInfix
    imap0
    listToAttrs
    nameValuePair
    optional
    replaceStrings
    stringToCharacters
    toLower
    ;

  allowedChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:-_";

  sanitizeKey =
    raw:
    let
      spaced = replaceStrings [ " " ] [ "-" ] (toLower raw);
      chars = stringToCharacters spaced;
      cleaned = concatStrings (map (c: if hasInfix c allowedChars then c else "") chars);
      stripColons =
        s:
        let
          dropLeft = str: if lib.hasPrefix ":" str then dropLeft (lib.removePrefix ":" str) else str;
          dropRight = str: if lib.hasSuffix ":" str then dropRight (lib.removeSuffix ":" str) else str;
        in
        dropRight (dropLeft s);
      collapsed = builtins.replaceStrings [ "::" ] [ ":" ] (stripColons cleaned);
      base = if collapsed == "" then "cmd" else collapsed;
    in
    base;

  assignKeys =
    commands:
    let
      step =
        acc: cmd:
        let
          base = sanitizeKey cmd.name;
          n = acc.counts.${base} or 0;
          key = if n == 0 then base else "${base}-${toString (n + 1)}";
        in
        {
          counts = acc.counts // {
            ${base} = n + 1;
          };
          items = acc.items ++ [
            {
              inherit key;
              inherit (cmd) name description;
            }
          ];
        };
      result = lib.foldl' step {
        counts = { };
        items = [ ];
      } commands;
    in
    result.items;

  keyed = assignKeys (motd.commands or [ ]);

  commands = listToAttrs (
    imap0 (
      i: item:
      nameValuePair item.key {
        description = item.description;
        exec = item.name;
        motd = if i < 5 then i + 1 else null;
      }
    ) keyed
  );

  env = map (label: {
    inherit label;
    value = "on";
  }) (motd.features or [ ]);

  hints = motd.hints or [ ];
  descriptionText = if hints == [ ] then "" else concatStringsSep "\n" hints;

  githubUrl = if github != null && github != "" then "https://github.com/${github}" else null;

  theme = if preludeCfg.theme != null then preludeCfg.theme else "minted";

  # Neutral defaults — product-specific chrome belongs in .stack/config.nix
  # (stackpanel.prelude.tagline / subtitle / settings), not the framework.
  taglineText =
    if preludeCfg.tagline != null && preludeCfg.tagline != "" then
      preludeCfg.tagline
    else
      "${name} devshell";
  subtitleText =
    if preludeCfg.subtitle != null && preludeCfg.subtitle != "" then
      preludeCfg.subtitle
    else
      "your environment is ready";

  status = {
    agent = {
      order = 100;
      label = "agent";
      check = ''
        command -v stackpanel >/dev/null 2>&1 || exit 1
        stackpanel motd --json 2>/dev/null | jq -e '.Agent.Running == true' >/dev/null
      '';
      ok = "up";
      fail = "down";
      failLevel = "warning";
      async = true;
    };
    services = {
      order = 200;
      label = "services";
      check = ''
        command -v stackpanel >/dev/null 2>&1 || exit 1
        json=$(stackpanel motd --json 2>/dev/null) || exit 1
        echo "$json" | jq -e '(.Services | length) == 0 or ([.Services[] | select(.Running != true)] | length) == 0' >/dev/null
      '';
      ok = "ok";
      fail = "down";
      failLevel = "warning";
      async = true;
    };
    health = {
      order = 300;
      label = "health";
      check = ''
        command -v stackpanel >/dev/null 2>&1 || exit 1
        stackpanel motd --json 2>/dev/null | jq -e '(.Issues | length) == 0' >/dev/null
      '';
      ok = "ok";
      fail = "issues";
      failLevel = "warning";
      async = true;
    };
  };

  docsPages =
    let
      root = projectRoot;
      readme =
        if root != null && builtins.pathExists (root + "/README.md") then
          { text = root + "/README.md"; }
        else
          null;
      quickStart =
        if root != null && builtins.pathExists (root + "/docs/quick-start.md") then
          {
            title = "Quick start";
            text = root + "/docs/quick-start.md";
          }
        else
          null;
    in
    if !(preludeCfg.docs.enable or true) then
      [ ]
    else
      filter (p: p != null) [
        readme
        quickStart
      ];

  # Escape hatch from stackpanel.prelude.settings (already prelude.* shaped).
  settings = preludeCfg.settings or { };

  base = {
    inherit theme commands;
    project = name;
    sort.groups = [
      "develop"
      "database"
      "deploy"
      "ops"
    ];
    motd = {
      enable = true;
      description.text = descriptionText;
      header = {
        tagline = {
          text = taglineText;
          subtitle = subtitleText;
          layout = "stack";
          align = "left";
        };
        background = false;
        statusHint = {
          layout = "inline";
          links = optional (githubUrl != null) {
            label = "github";
            url = githubUrl;
          };
        };
        inherit status;
      };
      inherit env;
      links = optional (githubUrl != null) {
        label = github;
        url = githubUrl;
      };
      recipes = { };
    };
    menu.enable = preludeCfg.menu.enable or true;
    prompt.enable = preludeCfg.prompt.enable or false;
    docs.pages = docsPages;
  };
in
# settings overlays façade (project/theme/commands/motd chrome, etc.)
lib.recursiveUpdate base settings
