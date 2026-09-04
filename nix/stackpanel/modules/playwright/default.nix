# ==============================================================================
# playwright - Reference extension for the reconciliation model
#
# Four concepts, each in its home:
#   - installation lives here, in files.entries, guarded by the enable flag
#   - convergence is ordinary reconciliation (write-files / preflight / setup):
#     bumping `version` below is a one-line edit that every adopter receives on
#     the next shell entry, with no doctor check and no addon involved
#   - adoption is the six-line `adoption` offer below, emitted unguarded
#   - observation is a runtime-scope doctor check with a fixCommand, because
#     installing browsers writes to ~/.cache, never to the repo
#
# Disabling the module removes playwright.config.ts and e2e.yml, drops the two
# package.json paths back to their baseline (bun's entries survive), and
# recomputes the shared .gitignore block. .stack/config.nix itself is untouched:
# it was never a managed output, so undoing adoption is a user edit.
# ==============================================================================
{ lib, ... }@args:
let
  meta = import ./meta.nix;
  inherit (import ../../lib/mkModule.nix { }) mkModule;
in
(mkModule {
  name = meta.id;
  inherit meta;
  source.type = "builtin";
  inherit (meta) features;
  inherit (meta) tags;
  inherit (meta) priority;
  healthcheckModule = meta.id;

  settings = {
    version = {
      type = lib.types.str;
      default = "1.48.0";
      description = "Pinned @playwright/test version written to package.json devDependencies.";
      example = "1.49.1";
    };
    packageJson = {
      type = lib.types.str;
      default = "package.json";
      description = "Repo-relative package.json that receives the test:e2e script and the devDependency.";
      example = "apps/web/package.json";
    };
  };

  adoption = {
    revision = 1;
    question = {
      type = "bool";
      label = "Add Playwright end-to-end testing?";
      description = "Generates playwright.config.ts, a GitHub e2e workflow, the test:e2e script and pins @playwright/test.";
      default = false;
      order = 30;
    };
    config.modules.playwright.enable = true;
  };

  config = cfg: {
    stackpanel.files.entries = {
      "playwright.config.ts" = {
        format = "text";
        writer = "full";
        adopt = "backup";
        path = ./files/playwright.config.ts;
        source = meta.id;
        description = "Playwright test runner configuration";
      };

      ".github/workflows/e2e.yml" = {
        format = "yaml";
        writer = "full";
        adopt = "backup";
        source = meta.id;
        description = "GitHub Actions workflow running the Playwright suite";
        value = {
          name = "e2e";
          on = {
            push.branches = [ "main" ];
            pull_request = { };
          };
          jobs.e2e = {
            runs-on = "ubuntu-latest";
            steps = [
              { uses = "actions/checkout@v4"; }
              { uses = "oven-sh/setup-bun@v2"; }
              {
                name = "Install";
                run = "bun install --frozen-lockfile";
              }
              {
                name = "Install browsers";
                run = "bunx playwright install --with-deps chromium";
              }
              {
                name = "Test";
                run = "bun run test:e2e";
              }
            ];
          };
        };
      };

      ".gitignore" = {
        format = "lines";
        writer = "block";
        dedupe = true;
        sort = true;
        lines = [
          "test-results/"
          "playwright-report/"
        ];
      };

      ${cfg.settings.packageJson} = {
        format = "json";
        writer = "paths";
        adopt = "backup";
        source = meta.id;
        description = "test:e2e script and pinned @playwright/test devDependency";
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
            value = cfg.settings.version;
          }
        ];
      };
    };

    # Browsers live in ~/.cache/ms-playwright, outside the repo, so this is
    # runtime scope with a fix command - never a repo-scope observation and
    # never something the doctor installs itself.
    stackpanel.doctor.playwright = {
      displayName = meta.name;
      browsers = {
        scope = "runtime";
        severity = "warning";
        description = "Playwright browsers are installed for this user";
        script = ''test -d "''${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}"'';
        fixCommand = "bunx playwright install";
        timeout = 5;
      };
    };
  };
})
  args
