# ==============================================================================
# files.nix
#
# Declarative file generation with hash-check caching, described on three
# independent axes:
#
#   format = "text" | "json" | "yaml" | "toml" | "lines" | "derivation" | "symlink"
#            how the content is produced
#   writer = "full" | "block" | "paths"
#            how much of the on-disk file stackpanel owns
#              full  - the whole file (default)
#              block - a marker-delimited block; user content outside is kept
#              paths - specific paths inside a structured (json/yaml/toml) doc
#   adopt  = "none" | "backup" | "refuse"
#            policy on FIRST CONTACT with a pre-existing, unmanaged file
#              none   - take it over silently (default)
#              backup - move it to <path>.backup, then take it over
#              refuse - fail loudly instead of taking it over
#
# Ongoing contention between two modules targeting one path is NOT an axis:
# use Nix module priorities (mkForce, mkOverride, mkBefore/mkAfter on `ops`).
# Two modules writing conflicting `set`/`remove` ops to the same path inside
# one file are detected at plan time and surfaced by `stack doctor`.
#
# Pure entries (writer = "full" and adopt = "none") are converted to Nix store
# derivations at eval time and written by the `write-files` script, which
# compares sha256 hashes and skips unchanged files. Source-aware entries
# (writer = "block" | "paths", or adopt != "none") are lowered into a preflight
# manifest applied by `stackpanel preflight run` / `stack setup`, so existing
# tracked files can be patched without invalidating pure-eval caches.
#
# Deprecated spellings (kept as sugar, always populated for legacy readers):
#   type    = "text" | "derivation" | "symlink" | "json" | "json-ops" | "line-set" | "line-map"
#   managed = "full" | "block"
#   json-ops  == format = "json";  writer = "paths"
#   line-set  == format = "lines"  (with `lines`)
#   line-map  == format = "lines"  (with `mapLines`)
#
# Usage (inline text):
#   stackpanel.files.entries.".github/workflows/ci.yml" = {
#     format = "text";
#     text = "name: CI\n...";
#   };
#
# Usage (YAML from a Nix value - deep-mergeable across modules):
#   stackpanel.files.entries.".github/workflows/e2e.yml" = {
#     format = "yaml";
#     value = { name = "e2e"; on.push = { }; };
#   };
#
# Usage (own specific paths inside package.json, applied by preflight):
#   stackpanel.files.entries."apps/web/package.json" = {
#     format = "json";
#     writer = "paths";
#     adopt = "backup";
#     ops = [
#       { op = "set"; path = "/scripts/dev"; value = "bun run dev"; }      # RFC 6901
#       { op = "set"; path = [ "devDependencies" "@x/y" ]; value = "1.0"; } # segments
#       { op = "appendUnique"; path = [ "keywords" ]; value = "stackpanel"; }
#     ];
#   };
#
#   The op vocabulary is deliberately NOT RFC 6902: 6902's `add` on an array
#   appends on every application, and this runs on every shell entry.
#   `appendUnique` is idempotent. `set` and `merge` are both required: a
#   deep-merging `set` could never replace a subtree with a smaller one.
#
# Usage (block-managed - preserves user content):
#   stackpanel.files.entries.".gitignore" = {
#     format = "lines";
#     writer = "block";
#     dedupe = true;
#     sort = true;
#     lines = [ "node_modules" ".env" ];
#   };
#
#   This produces a file like:
#     # ... user-written content above ...
#
#     # ── BEGIN stackpanel ──
#     # DO NOT EDIT between these markers — managed by stackpanel
#     .env
#     node_modules
#     # ── END stackpanel ──
#
#   User content outside the markers is never touched. On uninstall,
#   only the managed block is removed (the file is kept if non-empty).
#
# `.stack/config.nix` is deliberately never a file entry: everything here is an
# OUTPUT of evaluation and config.nix is the INPUT. The studio writes config.nix
# imperatively; a reconciled config.nix would revert every such write.
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.files;

  # Import util for debug logging
  inherit (config.stackpanel) util;

  q = lib.escapeShellArg;

  formatEnum = [
    "text"
    "json"
    "yaml"
    "toml"
    "lines"
    "derivation"
    "symlink"
  ];

  writerEnum = [
    "full"
    "block"
    "paths"
  ];

  adoptEnum = [
    "none"
    "backup"
    "refuse"
  ];

  legacyTypeEnum = [
    "text"
    "derivation"
    "symlink"
    "json"
    "json-ops"
    "line-set"
    "line-map"
  ];

  structuredFormats = [
    "json"
    "yaml"
    "toml"
  ];

  # Deprecated `type` -> `format`
  legacyFormatOf = {
    text = "text";
    derivation = "derivation";
    symlink = "symlink";
    json = "json";
    "json-ops" = "json";
    "line-set" = "lines";
    "line-map" = "lines";
  };

  # ── JSON Pointer (RFC 6901) ──────────────────────────────────────────────
  # `path` accepts either a list of segments or a JSON Pointer string. Pointers
  # are normalized to lists here so the Go side only ever sees segment lists.
  unescapePointerSegment = builtins.replaceStrings [ "~1" "~0" ] [ "/" "~" ];

  normalizeOpPath =
    path:
    if builtins.isList path then
      path
    else if path == "" then
      [ ]
    else if lib.hasPrefix "/" path then
      map unescapePointerSegment (lib.tail (lib.splitString "/" path))
    else
      throw "files: JSON Pointer paths must start with '/' (got \"${path}\"); pass a list of segments for raw keys";

  # ── Collision detection ──────────────────────────────────────────────────
  # `ops` lists from several modules are concatenated by the module system, so
  # two modules that `set` the same path silently race (last one wins in the
  # applier). Cooperative ops (merge/append/appendUnique) on one path are fine
  # and never flagged; a `set`/`remove` sharing a path with a differing op is.
  detectCollisions =
    ops:
    let
      groups = builtins.groupBy (op: builtins.toJSON op.path) ops;
      isReplacing = op: op.op == "set" || op.op == "remove";
      distinct = group: lib.unique (map (op: builtins.toJSON { inherit (op) op value; }) group);
      colliding = lib.filterAttrs (
        _: group:
        builtins.length group > 1 && builtins.any isReplacing group && builtins.length (distinct group) > 1
      ) groups;
    in
    lib.mapAttrsToList (_: group: {
      inherit ((builtins.head group)) path;
      count = builtins.length group;
      ops = map (op: { inherit (op) op value; }) group;
    }) colliding;

  # ── Entry submodule ──────────────────────────────────────────────────────
  opType = lib.types.submodule {
    options = {
      op = lib.mkOption {
        type = lib.types.enum [
          "set"
          "merge"
          "remove"
          "append"
          "appendUnique"
        ];
        description = ''
          Mutation applied at `path`:
          - `set`: replace the value (creates intermediate containers)
          - `merge`: deep-merge an object into the existing object
          - `remove`: delete the value
          - `append`: append to an array (not idempotent; prefer appendUnique)
          - `appendUnique`: append to an array unless an equal element exists
        '';
      };

      path = lib.mkOption {
        type = lib.types.either lib.types.str (lib.types.listOf lib.types.str);
        default = [ ];
        description = ''
          Location inside the structured document. Either a list of segments
          (`[ "scripts" "dev" ]`) or an RFC 6901 JSON Pointer string
          (`"/scripts/dev"`, with `~1` for `/` and `~0` for `~` in keys).
        '';
        example = "/scripts/test:e2e";
      };

      value = lib.mkOption {
        type = lib.types.anything;
        default = null;
        description = "Value used by set/merge/append/appendUnique operations.";
      };
    };
  };

  entryType = lib.types.submodule (
    { config, ... }:
    let
      resolvedFormat =
        if config.format != null then
          config.format
        else if config.type != null then
          legacyFormatOf.${config.type}
        else
          "text";

      resolvedWriter =
        if config.writer != null then
          config.writer
        else if config.type == "json-ops" then
          "paths"
        else if config.managed != null then
          config.managed
        else
          "full";
    in
    {
      options = {
        enable = lib.mkEnableOption "Generate this file" // {
          default = true;
        };

        format = lib.mkOption {
          type = lib.types.nullOr (lib.types.enum formatEnum);
          default = null;
          description = ''
            How the file content is produced:
            - 'text': inline `text` or a `path` read at eval time
            - 'json' / 'yaml' / 'toml': a Nix `value` serialized to that format
              (deep-merged across modules; with writer = "paths", `ops` instead)
            - 'lines': `lines` (plus truthy `mapLines` keys) joined by newlines
            - 'derivation': copy `drv`'s output
            - 'symlink': create a symbolic link to `target`
            Defaults to "text", or to the format implied by the deprecated `type`.
          '';
          example = "yaml";
        };

        writer = lib.mkOption {
          type = lib.types.nullOr (lib.types.enum writerEnum);
          default = null;
          description = ''
            How much of the on-disk file stackpanel owns:
            - 'full': the entire file (default). Overwritten on write, deleted when stale.
            - 'block': only a marker-delimited block. Content outside is preserved;
              on uninstall only the block is removed (file kept unless empty).
            - 'paths': only the paths named by `ops` inside a json/yaml/toml document.
              Unmanaged keys survive; a baseline is kept so managed paths can be
              restored when they are dropped. Applied by `stackpanel preflight run`.
          '';
          example = "paths";
        };

        adopt = lib.mkOption {
          type = lib.types.enum adoptEnum;
          default = "none";
          description = ''
            Policy on first contact with a pre-existing file that stackpanel did not
            create: "none" takes it over, "backup" moves the existing file to
            `<path>.backup` first, "refuse" fails loudly and leaves it alone.
            Adopted files are handled during preflight, not by the pure fast path.
          '';
          example = "backup";
        };

        # ── Deprecated spellings (sugar) ──────────────────────────────────
        type = lib.mkOption {
          type = lib.types.nullOr (lib.types.enum legacyTypeEnum);
          default = null;
          description = ''
            Deprecated: use `format` (and `writer = "paths"` for the former `json-ops`).
            Still accepted; when set it selects the equivalent `format`/`writer`.
            Manifests and the agent API report the closest legacy spelling regardless.
          '';
        };

        managed = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "full"
              "block"
            ]
          );
          default = null;
          description = "Deprecated: use `writer`. Still accepted as an alias for writer = \"full\" | \"block\".";
        };

        # ── Content sources ───────────────────────────────────────────────
        text = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Text content (format = 'text'). Mutually exclusive with `path`.";
        };

        path = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to file content (format = 'text'), read at eval time. Mutually exclusive with `text`.";
        };

        value = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Nix attrset serialized as JSON, YAML or TOML (format = json|yaml|toml, writer = full|block). Deep-merged across modules.";
        };

        jsonValue = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = "Deprecated alias of `value` (merged into it).";
        };

        ops = lib.mkOption {
          type = lib.types.listOf opType;
          default = [ ];
          description = ''
            Path operations applied by `stackpanel preflight run` when writer = "paths".
            Use this for structured tracked files like package.json where stackpanel
            should patch specific keys without replacing unrelated content.
          '';
        };

        lines = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Lines (format = 'lines'). Merged across modules via list concatenation.";
        };

        dedupe = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Remove duplicate lines from the output (format = 'lines').";
        };

        sort = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Sort lines alphabetically in the output (format = 'lines').";
        };

        mapLines = lib.mkOption {
          type = lib.types.attrsOf lib.types.bool;
          default = { };
          description = "Lines as an attrset (format = 'lines'). Keys with true become lines; false lets one module disable a line another added.";
        };

        drv = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = "Derivation whose outPath contains the file content (format = 'derivation').";
        };

        target = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Symlink target path (format = 'symlink'). Can be absolute (Nix store) or relative.";
        };

        blockLabel = lib.mkOption {
          type = lib.types.str;
          default = "stackpanel";
          description = ''
            Label used in the BEGIN/END markers for block-managed files.
            The markers will be: "# ── BEGIN <label> ──" / "# ── END <label> ──"
            Only used when writer = "block".
          '';
        };

        commentPrefix = lib.mkOption {
          type = lib.types.str;
          default = "#";
          description = ''
            Comment prefix for block markers. Defaults to "#" which works for
            gitignore, shell scripts, YAML, TOML, etc. Set to "//" for JSON-like,
            or ";" for INI files, etc. Only used when writer = "block".
          '';
        };

        mode = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional chmod mode (e.g. '0644', '0755').";
        };

        source = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Module or component that generated this file (for UI display).";
        };

        description = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Human-readable description of the file's purpose.";
        };

        # ── Resolved axes (read-only) ─────────────────────────────────────
        _format = lib.mkOption {
          type = lib.types.enum formatEnum;
          readOnly = true;
          internal = true;
          default = resolvedFormat;
          description = "Effective format after applying deprecated `type` sugar.";
        };

        _writer = lib.mkOption {
          type = lib.types.enum writerEnum;
          readOnly = true;
          internal = true;
          default = resolvedWriter;
          description = "Effective writer after applying deprecated `type`/`managed` sugar.";
        };

        _value = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          readOnly = true;
          internal = true;
          default = lib.recursiveUpdate config.jsonValue config.value;
          description = "Effective structured value (`jsonValue` merged into `value`).";
        };

        _ops = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          readOnly = true;
          internal = true;
          default = map (op: op // { path = normalizeOpPath op.path; }) config.ops;
          description = "Ops with JSON Pointer paths normalized to segment lists.";
        };

        _collisions = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          readOnly = true;
          internal = true;
          default = detectCollisions config._ops;
          description = "Conflicting ops (same path, differing set/remove) contributed by more than one definition.";
        };
      };
    }
  );

  # Closest legacy spelling of the resolved axes, so readers that still look
  # at `type`/`managed` (agent API, the files.json manifest) keep working.
  legacyTypeOf =
    e:
    if e.type != null then
      e.type
    else if e._format == "json" && e._writer == "paths" then
      "json-ops"
    else if e._format == "lines" then
      (if e.mapLines != { } && e.lines == [ ] then "line-map" else "line-set")
    else if e._format == "yaml" || e._format == "toml" then
      "text"
    else
      e._format;

  legacyManagedOf = e: if e._writer == "block" then "block" else "full";

  # ── Validation ───────────────────────────────────────────────────────────
  # Combinations that cannot be produced are rejected at eval time with a
  # message naming the file, instead of failing inside the writer script.
  validated =
    path: e: v:
    let
      fmt = e._format;
      writer = e._writer;
    in
    if writer == "paths" && !(builtins.elem fmt structuredFormats) then
      throw "File '${path}': writer = \"paths\" requires format = json | yaml | toml (got \"${fmt}\")"
    else if fmt == "symlink" && writer != "full" then
      throw "File '${path}': format = \"symlink\" only supports writer = \"full\""
    else if fmt == "symlink" && e.target == null then
      throw "File '${path}': format = \"symlink\" requires `target`"
    else if fmt == "derivation" && writer != "paths" && e.drv == null then
      throw "File '${path}': format = \"derivation\" requires `drv`"
    else
      v;

  # Only enabled entries are generated; disabled entries fall out of the
  # manifest and are cleaned up like any other stale file.
  enabledFiles = lib.filterAttrs (_: e: e.enable) cfg.entries;

  # Source-aware entries need the on-disk file (block/paths) or an adoption
  # decision, so they go through the preflight applier instead of the pure
  # hash-check fast path. Symlinks are always pure: adoption has no meaning.
  isSourceAwareFile =
    _path: e:
    e._format != "symlink" && (e._writer == "paths" || e._writer == "block" || e.adopt != "none");

  pureFiles = lib.filterAttrs (path: e: !(isSourceAwareFile path e)) enabledFiles;
  sourceAwareFiles = lib.filterAttrs isSourceAwareFile enabledFiles;

  hasFiles = builtins.length (builtins.attrNames enabledFiles) > 0;

  fileCount = builtins.length (builtins.attrNames pureFiles);

  # ── Resolve content ──────────────────────────────────────────────────────
  resolveTextContent =
    path: e:
    let
      fmt = e._format;
      hasText = e.text != null;
      hasPath = e.path != null;
    in
    if builtins.elem fmt structuredFormats then
      builtins.toJSON e._value
    else if fmt == "lines" then
      let
        raw = e.lines ++ lib.attrNames (lib.filterAttrs (_: v: v) e.mapLines);
        deduped = if e.dedupe then lib.unique raw else raw;
        sorted = if e.sort then lib.sort lib.lessThan deduped else deduped;
      in
      lib.concatStringsSep "\n" sorted + "\n"
    else if hasText && hasPath then
      throw "File '${path}': cannot specify both 'text' and 'path' - use one or the other"
    else if hasPath then
      builtins.readFile e.path
    else if hasText then
      e.text
    else
      throw "File '${path}': format 'text' requires either 'text' or 'path' to be set";

  # ── Store path resolution ────────────────────────────────────────────────
  # Convert each entry into a Nix store derivation. This is the single source
  # of truth for file content — the writer script and drift check both use it.
  #
  # Structured formats are rendered at build time (jq / remarshal) so the store
  # content matches what lands on disk byte for byte.
  mkStorePath =
    path: e:
    validated path e (
      let
        fmt = e._format;
        baseName = builtins.baseNameOf path;
        rawJson = pkgs.writeText "${baseName}.raw" (resolveTextContent path e);
      in
      if e._writer == "paths" then
        null # applied in place by preflight; nothing to stage
      else if fmt == "text" || fmt == "lines" then
        pkgs.writeText baseName (resolveTextContent path e)
      else if fmt == "json" then
        pkgs.runCommand baseName { nativeBuildInputs = [ pkgs.jq ]; } ''
          ${pkgs.jq}/bin/jq '.' ${rawJson} > $out
        ''
      else if fmt == "yaml" then
        pkgs.runCommand baseName { nativeBuildInputs = [ pkgs.remarshal ]; } ''
          json2yaml ${rawJson} > $out
        ''
      else if fmt == "toml" then
        pkgs.runCommand baseName { nativeBuildInputs = [ pkgs.remarshal ]; } ''
          json2toml ${rawJson} > $out
        ''
      else if fmt == "derivation" then
        e.drv
      else
        null # symlink doesn't have a store path
    );

  # Attrset of { path = storePath; } for all non-symlink entries
  storePathsByFile = lib.mapAttrs (
    path: e: if e._format == "symlink" then null else mkStorePath path e
  ) enabledFiles;

  # ── Manifest (for state tracking and fast path) ──────────────────────────
  manifestEntries = lib.mapAttrsToList (
    path: e:
    let
      fmt = e._format;
      storePath = storePathsByFile.${path};
      contentSource =
        if fmt == "text" then
          if e.path != null then
            "path"
          else if e.text != null then
            "inline"
          else
            "unknown"
        else if builtins.elem fmt structuredFormats then
          fmt
        else if fmt == "derivation" then
          "derivation"
        else if fmt == "symlink" then
          "symlink"
        else
          "unknown";
    in
    {
      inherit path;
      type = legacyTypeOf e;
      format = fmt;
      writer = e._writer;
      managed = legacyManagedOf e;
      inherit (e) blockLabel;
      inherit (e) commentPrefix;
      inherit (e) mode;
      inherit (e) source;
      inherit (e) description;
      inherit (e) target;
      inherit contentSource;
      storePath = if storePath != null then builtins.toString storePath else null;
    }
  ) pureFiles;

  manifestJson = builtins.toJSON {
    version = 2;
    files = manifestEntries;
  };

  manifestDrv = pkgs.writeText "stackpanel-files-manifest.json" manifestJson;

  # Source-aware entries lower onto the applier's vocabulary:
  #   <format>-ops  (writer = "paths")   json-ops | yaml-ops | toml-ops
  #   block         (writer = "block")
  #   full-copy     (adopted whole files)
  # "json-ops" is kept verbatim so existing preflight state files stay valid.
  preflightManifestEntries = lib.mapAttrsToList (
    path: e:
    let
      storePath = storePathsByFile.${path};
    in
    validated path e (
      if e._writer == "paths" then
        {
          inherit path;
          type = "${e._format}-ops";
          format = e._format;
          inherit (e) adopt;
          inherit (e) mode;
          ops = e._ops;
          collisions = e._collisions;
        }
      else if e._writer == "block" then
        {
          inherit path;
          type = "block";
          format = e._format;
          inherit (e) adopt;
          inherit (e) mode;
          inherit (e) blockLabel;
          inherit (e) commentPrefix;
          storePath = if storePath != null then builtins.toString storePath else null;
        }
      else
        {
          inherit path;
          type = "full-copy";
          format = e._format;
          inherit (e) adopt;
          inherit (e) mode;
          storePath = if storePath != null then builtins.toString storePath else null;
        }
    )
  ) sourceAwareFiles;

  preflightManifestJson = builtins.toJSON {
    version = 1;
    files = preflightManifestEntries;
  };

  preflightManifestDrv = pkgs.writeText "stackpanel-files-preflight.json" preflightManifestJson;

  # ── Plan view (for `stack doctor` / `stack setup`) ───────────────────────
  # One record per enabled entry with everything the reconciler needs to
  # diff against disk without building anything: cheap content for text and
  # lines, the structured value for json/yaml/toml, ops for path writers.
  planEntries = lib.mapAttrsToList (
    path: e:
    let
      fmt = e._format;
      storePath = storePathsByFile.${path};
      sourceAware = isSourceAwareFile path e;
    in
    {
      inherit path;
      format = fmt;
      writer = e._writer;
      inherit (e)
        adopt
        mode
        blockLabel
        commentPrefix
        source
        description
        target
        ;
      kind = if sourceAware then "preflight" else "pure";
      manifestType =
        if !sourceAware then
          (if fmt == "symlink" then "symlink" else "pure")
        else if e._writer == "paths" then
          "${fmt}-ops"
        else if e._writer == "block" then
          "block"
        else
          "full-copy";
      storePath = if storePath != null then builtins.toString storePath else null;
      content =
        if e._writer != "paths" && (fmt == "text" || fmt == "lines") then
          resolveTextContent path e
        else
          null;
      structured = if e._writer != "paths" && builtins.elem fmt structuredFormats then e._value else null;
      ops = if e._writer == "paths" then e._ops else [ ];
      collisions = e._collisions;
    }
  ) enabledFiles;

  # ── Manifest hash (fast path) ───────────────────────────────────────────
  # Compute a single hash from all (path, storePath) pairs. When this hash
  # matches the on-disk manifest hash, we know nothing changed and can skip
  # all individual file checks.
  #
  # We include symlink targets in the hash too so symlink target changes
  # are detected.
  manifestHashInput = lib.concatMapStringsSep "\n" (
    entry:
    let
      value =
        if entry.storePath != null then
          entry.storePath
        else if entry.target or null != null then
          "symlink:${entry.target}"
        else
          "unknown";
    in
    "${entry.path}=${value}"
  ) manifestEntries;

  manifestHash = builtins.hashString "sha256" manifestHashInput;

  # ── Per-file write snippets ──────────────────────────────────────────────
  mkWriteSnippet =
    path: e:
    let
      inherit (e) mode;
      fmt = e._format;
      writer = e._writer;
      storePath = storePathsByFile.${path};
      symlinkTarget = e.target;
      beginMarker = "${e.commentPrefix} ── BEGIN ${e.blockLabel} ──";
      endMarker = "${e.commentPrefix} ── END ${e.blockLabel} ──";
      noEditNotice = "${e.commentPrefix} DO NOT EDIT between these markers — managed by stackpanel";
    in
    if fmt == "symlink" then
      # Symlinks are always recreated (cheap operation, no hash check needed)
      ''
        # ${path} (symlink)
        mkdir -p "$(dirname ${q path})"
        if [[ "$FORCE" == "0" ]] && [[ -L ${q path} ]] && [[ "$(readlink ${q path})" == ${q symlinkTarget} ]]; then
          UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
          if [[ "''${STACKPANEL_DEBUG:-}" == "1" ]] || [[ "$VERBOSE" == "1" ]]; then
            echo "  skip ${path} (symlink unchanged)"
          fi
        else
          rm -f ${q path} 2>/dev/null || true
          ln -s ${q symlinkTarget} ${q path}
          WRITTEN_COUNT=$((WRITTEN_COUNT + 1))
          echo "  write ${path} -> ${symlinkTarget}"
        fi
      ''
    else if writer == "block" then
      # Block mode: only manage a marker-delimited section within the file.
      # User content outside the markers is preserved.
      ''
        # ${path} (${fmt}, block-managed)
        _src=${storePath}
        _dst=${q path}
        _begin_marker=${q beginMarker}
        _end_marker=${q endMarker}
        _no_edit=${q noEditNotice}

        # Build the full managed block (markers + content)
        _block_content="$(printf '%s\n%s\n%s\n%s' "$_begin_marker" "$_no_edit" "$(cat "$_src")" "$_end_marker")"

        mkdir -p "$(dirname "$_dst")"

        if [[ ! -f "$_dst" ]]; then
          # File doesn't exist — create with just the managed block
          printf '%s\n' "$_block_content" > "$_dst"
          ${lib.optionalString (mode != null) ''chmod ${q mode} "$_dst"''}
          WRITTEN_COUNT=$((WRITTEN_COUNT + 1))
          echo "  write ${path} (block, new file)"
        elif ! grep -qF "$_begin_marker" "$_dst"; then
          # File exists but no managed block — append
          # Add a blank line separator if file doesn't end with one
          if [[ -s "$_dst" ]] && [[ "$(tail -c1 "$_dst")" != "" ]]; then
            printf '\n' >> "$_dst"
          fi
          printf '\n%s\n' "$_block_content" >> "$_dst"
          ${lib.optionalString (mode != null) ''chmod ${q mode} "$_dst"''}
          WRITTEN_COUNT=$((WRITTEN_COUNT + 1))
          echo "  write ${path} (block, appended)"
        else
          # File exists with managed block — extract current block and compare
          _current_block=$(${pkgs.gawk}/bin/awk -v begin="$_begin_marker" -v end="$_end_marker" '
            $0 == begin { found=1 }
            found { block = block $0 "\n" }
            $0 == end { found=0 }
            END { printf "%s", block }
          ' "$_dst")

          if [[ "$FORCE" == "0" ]] && [[ "$_current_block" == "$_block_content"$'\n' ]]; then
            UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
            if [[ "''${STACKPANEL_DEBUG:-}" == "1" ]] || [[ "$VERBOSE" == "1" ]]; then
              echo "  skip ${path} (block unchanged)"
            fi
          else
            # Replace block between markers (inclusive) using awk
            ${pkgs.gawk}/bin/awk -v begin="$_begin_marker" -v end="$_end_marker" -v replacement="$_block_content" '
              $0 == begin { skip=1; if (!printed) { print replacement; printed=1 }; next }
              skip && $0 == end { skip=0; next }
              !skip { print }
            ' "$_dst" > "$_dst.sp-tmp" && mv "$_dst.sp-tmp" "$_dst"
            ${lib.optionalString (mode != null) ''chmod ${q mode} "$_dst"''}
            WRITTEN_COUNT=$((WRITTEN_COUNT + 1))
            echo "  write ${path} (block, updated)"
          fi
        fi
      ''
    else
      # Full mode (default): hash-check before writing entire file
      ''
        # ${path} (${fmt})
        _src=${storePath}
        _dst=${q path}
        if [[ "$FORCE" == "0" ]] && [[ -f "$_dst" ]] && [[ "$(${pkgs.coreutils}/bin/sha256sum "$_dst" | cut -d' ' -f1)" == "$(${pkgs.coreutils}/bin/sha256sum "$_src" | cut -d' ' -f1)" ]]; then
          UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
          if [[ "''${STACKPANEL_DEBUG:-}" == "1" ]] || [[ "$VERBOSE" == "1" ]]; then
            echo "  skip ${path} (unchanged)"
          fi
        else
          mkdir -p "$(dirname "$_dst")"
          cat "$_src" > "$_dst"
          ${lib.optionalString (mode != null) ''chmod ${q mode} "$_dst"''}
          WRITTEN_COUNT=$((WRITTEN_COUNT + 1))
          echo "  write ${path}"
        fi
      '';

  # JSON array of all current file paths (for the cleanup diff)
  currentPathsJson = builtins.toJSON (builtins.attrNames enabledFiles);

  manifestPresenceCheck = lib.concatLines (
    lib.mapAttrsToList (path: _: ''
      if [[ ! -e ${q path} ]]; then
        MISSING_CURRENT_FILES=1
      fi
    '') pureFiles
  );

  # ── Writer script ────────────────────────────────────────────────────────
  writerDrv = pkgs.writeShellApplication {
    name = "write-files";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.gawk
    ];
    text = ''
      set -euo pipefail

      # ── Parse flags ──────────────────────────────────────────────────────
      FORCE=0
      VERBOSE=0
      for arg in "$@"; do
        case "$arg" in
          --force|-f) FORCE=1 ;;
          --verbose|-v) VERBOSE=1 ;;
          --help|-h)
            echo "Usage: write-files [--force] [--verbose]"
            echo "  --force   Skip hash checks, rewrite all files"
            echo "  --verbose Show per-file skip/write details"
            exit 0
            ;;
        esac
      done

      # Determine repo root
      ROOT="''${STACKPANEL_ROOT:-}"
      if [[ -z "$ROOT" ]]; then
        echo "ERROR: STACKPANEL_ROOT is not set. (Stackpanel core should set it.)" >&2
        exit 1
      fi

      cd "$ROOT"

      STATE_DIR="''${STACKPANEL_STATE_DIR:-$ROOT/.stack/profile}"
      MANIFEST_FILE="$STATE_DIR/.files-manifest"

      # ── Manifest fast path ──────────────────────────────────────────────
      # If the manifest hash matches, nothing changed — skip everything.
      MANIFEST_HASH="${manifestHash}"
      MISSING_CURRENT_FILES=0
      ${manifestPresenceCheck}
      if [[ "$FORCE" == "0" ]] && [[ -f "$MANIFEST_FILE" ]] && [[ "$(cat "$MANIFEST_FILE")" == "$MANIFEST_HASH" ]]; then
        if [[ "$MISSING_CURRENT_FILES" == "0" ]]; then
          if [[ "''${STACKPANEL_DEBUG:-}" == "1" ]] || [[ "$VERBOSE" == "1" ]]; then
            echo "files: all ${toString fileCount} files unchanged (skipping)"
          fi
          exit 0
        fi
      fi

      # ── Cleanup stale files from previous generation ─────────────────────
      OLD_MANIFEST="$STATE_DIR/files.json"
      REMOVED_COUNT=0
      if [[ -f "$OLD_MANIFEST" ]]; then
        CURRENT_PATHS='${currentPathsJson}'

        # Extract old file entries from the manifest (path + writer + markers)
        OLD_ENTRIES=$(jq -r '.files[] | "\(.path)\t\(.writer // .managed // "full")\t\(.commentPrefix // "#")\t\(.blockLabel // "stackpanel")"' "$OLD_MANIFEST" 2>/dev/null) || OLD_ENTRIES=""

        while IFS=$'\t' read -r old_path old_managed old_comment_prefix old_block_label; do
          [[ -z "$old_path" ]] && continue
          # Check if this path is still in the current file set
          if ! echo "$CURRENT_PATHS" | jq -e --arg p "$old_path" 'index($p) != null' >/dev/null 2>&1; then
            # This file is stale
            if [[ "$old_managed" == "block" ]]; then
              # Block-managed: strip the managed block instead of deleting
              if [[ -f "$old_path" ]]; then
                _begin="$old_comment_prefix ── BEGIN $old_block_label ──"
                _end="$old_comment_prefix ── END $old_block_label ──"
                if grep -qF "$_begin" "$old_path"; then
                  # Remove the block (and any single blank line immediately before it)
                  ${pkgs.gawk}/bin/awk -v begin="$_begin" -v end="$_end" '
                    $0 == begin { skip=1; if (prev_blank) { prev_blank=0 }; next }
                    skip && $0 == end { skip=0; next }
                    skip { next }
                    /^[[:space:]]*$/ { prev_blank=1; prev_line=$0; next }
                    { if (prev_blank) { print prev_line; prev_blank=0 }; print }
                    END { if (prev_blank) print prev_line }
                  ' "$old_path" > "$old_path.sp-tmp" && mv "$old_path.sp-tmp" "$old_path"
                  echo "  remove $old_path (stale block stripped)"
                  REMOVED_COUNT=$((REMOVED_COUNT + 1))
                  # If the file is now empty (or only whitespace), remove it
                  if [[ ! -s "$old_path" ]] || ! grep -q '[^[:space:]]' "$old_path"; then
                    rm -f "$old_path"
                    echo "  remove $old_path (empty after block removal)"
                  fi
                fi
              fi
            else
              # Full-managed: delete the entire file
              if [[ -e "$old_path" || -L "$old_path" ]]; then
                rm -f "$old_path" 2>/dev/null || true
                echo "  remove $old_path (stale)"
                REMOVED_COUNT=$((REMOVED_COUNT + 1))

                # Clean up empty parent directories (up to repo root)
                dir=$(dirname "$old_path")
                while [[ "$dir" != "." && "$dir" != "/" ]]; do
                  if [[ -d "$dir" ]] && [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
                    rmdir "$dir" 2>/dev/null || true
                  else
                    break
                  fi
                  dir=$(dirname "$dir")
                done
              fi
            fi
          fi
        done <<< "$OLD_ENTRIES"
      fi

      # ── Write current files (with hash check) ───────────────────────────
      WRITTEN_COUNT=0
      UNCHANGED_COUNT=0

      ${lib.concatLines (lib.mapAttrsToList mkWriteSnippet pureFiles)}

      # ── Write manifest ──────────────────────────────────────────────────
      mkdir -p "$STATE_DIR"
      cat ${manifestDrv} > "$STATE_DIR/files.json"

      # Write manifest hash for fast path on next run
      echo -n "$MANIFEST_HASH" > "$MANIFEST_FILE"

      # ── Summary ─────────────────────────────────────────────────────────
      PARTS=""
      if [[ "$WRITTEN_COUNT" -gt 0 ]]; then
        PARTS="$WRITTEN_COUNT written"
      fi
      if [[ "$UNCHANGED_COUNT" -gt 0 ]]; then
        if [[ -n "$PARTS" ]]; then PARTS="$PARTS, "; fi
        PARTS="''${PARTS}$UNCHANGED_COUNT unchanged"
      fi
      if [[ "$REMOVED_COUNT" -gt 0 ]]; then
        if [[ -n "$PARTS" ]]; then PARTS="$PARTS, "; fi
        PARTS="''${PARTS}$REMOVED_COUNT removed"
      fi
      echo "files: $PARTS"
    '';
  };

  # ── Drift check derivation ──────────────────────────────────────────────
  # A derivation that verifies on-disk files match their expected store content.
  # Used via `nix flake check` or exposed as a moduleCheck. `stack doctor`
  # performs the same comparison in Go and reports drift as a finding.
  #
  # NOTE: This check requires IFD (import-from-derivation) or must be run
  # against a checkout. We build it as a script that takes ROOT as an argument.
  driftCheckScript =
    let
      # Only check files that have a store path (skip symlinks)
      pureStorePathsByFile = lib.filterAttrs (path: _: builtins.hasAttr path pureFiles) storePathsByFile;
      checkableFiles = lib.filterAttrs (_: v: v != null) pureStorePathsByFile;

      # Full-managed files: compare entire file hash
      fullManagedFiles = lib.filterAttrs (path: _: pureFiles.${path}._writer == "full") checkableFiles;
      fullCheckSnippets = lib.mapAttrsToList (path: storePath: ''
        _dst="$ROOT/${path}"
        if [[ ! -f "$_dst" ]]; then
          echo "DRIFT: ${path} is missing (expected from store)"
          DRIFT=1
        else
          _expected=$(${pkgs.coreutils}/bin/sha256sum ${storePath} | cut -d' ' -f1)
          _actual=$(${pkgs.coreutils}/bin/sha256sum "$_dst" | cut -d' ' -f1)
          if [[ "$_expected" != "$_actual" ]]; then
            echo "DRIFT: ${path} does not match generated content"
            DRIFT=1
          fi
        fi
      '') fullManagedFiles;

      # Also check symlinks
      symlinkFiles = lib.filterAttrs (_: e: e._format == "symlink") pureFiles;
      symlinkSnippets = lib.mapAttrsToList (path: e: ''
        _dst="$ROOT/${path}"
        if [[ ! -L "$_dst" ]]; then
          echo "DRIFT: ${path} is not a symlink (expected -> ${e.target})"
          DRIFT=1
        elif [[ "$(readlink "$_dst")" != ${q e.target} ]]; then
          echo "DRIFT: ${path} points to $(readlink "$_dst"), expected ${e.target}"
          DRIFT=1
        fi
      '') symlinkFiles;
    in
    pkgs.writeShellApplication {
      name = "check-files-drift";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gawk
      ];
      text = ''
        set -euo pipefail

        ROOT="''${1:-''${STACKPANEL_ROOT:-}}"
        if [[ -z "$ROOT" ]]; then
          echo "Usage: check-files-drift [ROOT]" >&2
          echo "  or set STACKPANEL_ROOT" >&2
          exit 1
        fi

        cd "$ROOT"
        DRIFT=0

        ${lib.concatLines fullCheckSnippets}
        ${lib.concatLines symlinkSnippets}

        if [[ "$DRIFT" == "1" ]]; then
          echo ""
          echo "Some generated files are out of date."
          echo "Run 'write-files' to fix."
          exit 1
        else
          echo "All ${toString fileCount} generated files are up to date."
        fi
      '';
    };
in
{
  options.stackpanel.files = {
    enable = lib.mkEnableOption "file generation" // {
      default = true;
    };

    entries = lib.mkOption {
      description = ''
        Files to generate into the repo. Keys are file paths relative to repo root.

        Each entry is described on three axes:
          - `format`: how content is produced
            (text | json | yaml | toml | lines | derivation | symlink)
          - `writer`: how much of the file stackpanel owns
            (full | block | paths)
          - `adopt`: first-contact policy for a pre-existing file
            (none | backup | refuse)

        The deprecated `type` / `managed` spellings are still accepted:
        `type = "json-ops"` is `format = "json"; writer = "paths"`,
        `type = "line-set"` / `"line-map"` are `format = "lines"`, and
        `managed = "block"` is `writer = "block"`.
      '';
      type = lib.types.attrsOf entryType;
      default = { };
    };

    _storePathsByFile = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      internal = true;
      description = "Resolved Nix store paths for each generated file entry. Null for symlinks and path writers.";
    };

    _writerDrv = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      default = writerDrv;
      description = "The write-files executable for the current generation. `stack setup` realizes it after a config mutation to reconcile pure files without a shell re-entry.";
    };

    _preflightManifestDrv = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      default = preflightManifestDrv;
      description = "Store file holding the preflight (source-aware) manifest for the current generation.";
    };

    _plan = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      readOnly = true;
      internal = true;
      default = planEntries;
      description = ''
        Reconciler view of every enabled entry: resolved axes, store path, cheap
        content (text/lines), structured value (json/yaml/toml), ops (paths) and
        detected collisions. Read by `stack doctor` / `stack setup` and by the
        speculative evaluation behind addon adoption. Evaluating it builds nothing.
      '';
    };
  };

  config = lib.mkIf hasFiles {
    stackpanel.files._storePathsByFile = storePathsByFile;

    # Make the executable available in PATH
    stackpanel.devshell.packages = [
      writerDrv
      driftCheckScript
    ];

    stackpanel.devshell.env = {
      # Current-generation manifest of pure files (path -> store path). The Go
      # reconciler diffs this against disk to report drift without running
      # write-files.
      STACKPANEL_FILES_MANIFEST = "${manifestDrv}";
    }
    // lib.optionalAttrs (builtins.length preflightManifestEntries > 0) {
      STACKPANEL_FILES_PREFLIGHT_MANIFEST = "${preflightManifestDrv}";
    };

    # Run write-files on shell entry (after core setup which sets STACKPANEL_ROOT)
    stackpanel.devshell.hooks.main = [
      ''
        ${util.log.debug "files: invoking write-files on shell entry"}
        ${writerDrv}/bin/write-files
      ''
    ];
  };
}
