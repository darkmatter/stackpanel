# ==============================================================================
# files.test.nix
#
# Unit tests for the files schema refactor: the deprecated `type`/`managed`
# spellings must lower onto the `format`/`writer` axes exhaustively, JSON
# Pointer paths must normalize to segment lists, and plan-time collision
# detection must flag conflicting `set` ops while leaving cooperative ops alone.
#
# Run with: nix eval --impure -f nix/stackpanel/files/files.test.nix
# ==============================================================================
let
  pkgs = import <nixpkgs> { }; # @impure test harness only
  inherit (pkgs) lib;

  evalFiles =
    entries:
    (lib.evalModules {
      modules = [
        ../files
        {
          options.stackpanel = {
            util = lib.mkOption {
              type = lib.types.attrs;
              default = {
                log.debug = _: "";
              };
            };
            devshell.packages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
            };
            devshell.env = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
            };
            devshell.hooks.main = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          };
          config.stackpanel.files.entries = entries;
        }
      ];
      specialArgs = {
        inherit pkgs;
      };
    }).config.stackpanel.files;

  # Every legacy `type` and `managed` spelling and the axes it must resolve to.
  legacyCases = [
    {
      name = "text";
      entry = {
        type = "text";
        text = "x";
      };
      format = "format-text";
      writer = "full";
    }
    {
      name = "derivation";
      entry = {
        type = "derivation";
        drv = pkgs.writeText "d" "x";
      };
      format = "format-derivation";
      writer = "full";
    }
    {
      name = "symlink";
      entry = {
        type = "symlink";
        target = "/x";
      };
      format = "format-symlink";
      writer = "full";
    }
    {
      name = "json";
      entry = {
        type = "json";
        jsonValue.a = 1;
      };
      format = "format-json";
      writer = "full";
    }
    {
      name = "json-ops";
      entry = {
        type = "json-ops";
        ops = [
          {
            op = "set";
            path = [ "a" ];
            value = 1;
          }
        ];
      };
      format = "format-json";
      writer = "paths";
    }
    {
      name = "line-set";
      entry = {
        type = "line-set";
        lines = [ "a" ];
      };
      format = "format-lines";
      writer = "full";
    }
    {
      name = "line-map";
      entry = {
        type = "line-map";
        mapLines.a = true;
      };
      format = "format-lines";
      writer = "full";
    }
    {
      name = "managed-block";
      entry = {
        type = "line-set";
        managed = "block";
        lines = [ "a" ];
      };
      format = "format-lines";
      writer = "block";
    }
  ];

  legacyResults = map (
    c:
    let
      files = evalFiles { "f-${c.name}" = c.entry; };
      e = files.entries."f-${c.name}";
      # legacy readers still see the deprecated spelling
      inherit ((builtins.head files._plan)) manifestType;
    in
    {
      inherit (c) name;
      passed = ("format-" + e._format) == c.format && e._writer == c.writer;
      got = {
        format = e._format;
        writer = e._writer;
        inherit manifestType;
      };
    }
  ) legacyCases;

  testLegacySugar = {
    name = "legacy-type-and-managed-lower-onto-axes";
    passed = builtins.all (r: r.passed) legacyResults;
    details = legacyResults;
  };

  # RFC 6901 pointers and segment lists coexist and normalize identically.
  pointerFiles = evalFiles {
    "package.json" = {
      format = "json";
      writer = "paths";
      ops = [
        {
          op = "set";
          path = "/scripts/test:e2e";
          value = "playwright test";
        }
        {
          op = "set";
          path = [
            "devDependencies"
            "@playwright/test"
          ];
          value = "1.48.0";
        }
        {
          op = "set";
          path = "/a~1b/c~0d";
          value = 1;
        }
      ];
    };
  };
  pointerOps = pointerFiles.entries."package.json"._ops;
  testJsonPointer = {
    name = "json-pointer-normalizes-to-segments";
    passed =
      (builtins.elemAt pointerOps 0).path == [
        "scripts"
        "test:e2e"
      ]
      &&
        (builtins.elemAt pointerOps 1).path == [
          "devDependencies"
          "@playwright/test"
        ]
      &&
        (builtins.elemAt pointerOps 2).path == [
          "a/b"
          "c~d"
        ]
      && pointerFiles.entries."package.json"._collisions == [ ];
    got = map (o: o.path) pointerOps;
  };

  # Two definitions setting one path with different values collide; two merges
  # or two appendUnique on one path cooperate and are never flagged.
  collisionFiles = evalFiles {
    "package.json" = lib.mkMerge [
      {
        format = "json";
        writer = "paths";
        ops = [
          {
            op = "set";
            path = [ "name" ];
            value = "one";
          }
          {
            op = "merge";
            path = [ "scripts" ];
            value.dev = "x";
          }
          {
            op = "appendUnique";
            path = [ "keywords" ];
            value = "a";
          }
        ];
      }
      {
        ops = [
          {
            op = "set";
            path = [ "name" ];
            value = "two";
          }
          {
            op = "merge";
            path = [ "scripts" ];
            value.test = "y";
          }
          {
            op = "appendUnique";
            path = [ "keywords" ];
            value = "b";
          }
        ];
      }
    ];
  };
  collisions = collisionFiles.entries."package.json"._collisions;
  testCollisions = {
    name = "collision-detection-flags-set-not-cooperative-ops";
    passed =
      builtins.length collisions == 1
      && (builtins.head collisions).path == [ "name" ]
      && (builtins.head collisions).count == 2;
    got = collisions;
  };

  # yaml/toml formats render through remarshal and never need a legacy type.
  structuredFiles = evalFiles {
    "e2e.yml" = {
      format = "yaml";
      value.name = "e2e";
    };
    "cfg.toml" = {
      format = "toml";
      value.name = "cfg";
    };
  };
  testStructuredFormats = {
    name = "yaml-and-toml-formats-have-store-paths";
    passed =
      structuredFiles._storePathsByFile."e2e.yml" != null
      && structuredFiles._storePathsByFile."cfg.toml" != null
      &&
        (builtins.head (builtins.filter (e: e.path == "e2e.yml") structuredFiles._plan)).structured == {
          name = "e2e";
        };
  };

  # Disabled entries drop out of every view.
  disabledFiles = evalFiles {
    "on.txt" = {
      text = "x";
    };
    "off.txt" = {
      text = "y";
      enable = false;
    };
  };
  testDisabled = {
    name = "disabled-entries-are-not-planned";
    passed = map (e: e.path) disabledFiles._plan == [ "on.txt" ];
  };

  allTests = [
    testLegacySugar
    testJsonPointer
    testCollisions
    testStructuredFormats
    testDisabled
  ];
  failedTests = builtins.filter (t: !t.passed) allTests;
in
{
  total = builtins.length allTests;
  passed = builtins.length allTests - builtins.length failedTests;
  failed = builtins.length failedTests;
  allPassed = failedTests == [ ];
  results = map (t: {
    inherit (t) name passed;
  }) allTests;
  failedDetails = failedTests;
}
