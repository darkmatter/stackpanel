# Secrets schema + code generation for TypeScript, Python, Go
# Standalone module - no flake-parts dependency
#
# Define your secrets schema once, get:
#   - Type-safe env access in your language of choice
#   - Nullable types for optional secrets
#   - PUBLIC_* prefix for client-safe values (non-sensitive)
#
{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) concatStringsSep concatMapStringsSep optionalString;
  cfg = config.stackpanel.secrets;

  # Schema entries as list with name included
  schemaEntries =
    lib.mapAttrsToList (name: opts: opts // {inherit name;}) cfg.schema;

  # Split by sensitivity
  sensitiveSecrets = lib.filter (s: s.sensitive) schemaEntries;
  publicSecrets = lib.filter (s: !s.sensitive) schemaEntries;
  allSecrets = sensitiveSecrets ++ publicSecrets;

  # ══════════════════════════════════════════════════════════════════════════════
  # TypeScript Code Generation
  # ══════════════════════════════════════════════════════════════════════════════

  tsServerGetter = s: let
    type =
      if s.required
      then "string"
      else "string | undefined";
    desc =
      if s.description != ""
      then s.description
      else s.name;
    tag =
      if s.required
      then "@required"
      else "@optional";
    bodyLines =
      if s.required
      then [
        "    const value = process.env.${s.name};"
        ''if (!value) throw new Error("Missing required env var: ${s.name}");''
        "    return value;"
      ]
      else ["    return process.env.${s.name};"];
  in
    concatStringsSep "\n" ([
        "  /**"
        "   * ${desc}"
        "   * ${tag}"
        "   */"
        "  get ${s.name}(): ${type} {"
      ]
      ++ bodyLines ++ ["  }"]);

  tsClientGetter = s: let
    type =
      if s.required
      then "string"
      else "string | undefined";
    desc =
      if s.description != ""
      then s.description
      else s.name;
    tag =
      if s.required
      then "@required"
      else "@optional";
    bodyLines =
      if s.required
      then [
        "    const value = process.env.PUBLIC_${s.name} ?? process.env.NEXT_PUBLIC_${s.name};"
        ''
          if (!value) throw new Error("Missing required env var: PUBLIC_${s.name}");''
        "    return value;"
      ]
      else [
        "    return process.env.PUBLIC_${s.name} ?? process.env.NEXT_PUBLIC_${s.name};"
      ];
  in
    concatStringsSep "\n" ([
        "  /**"
        "   * ${desc}"
        "   * ${tag}"
        "   */"
        "  get ${s.name}(): ${type} {"
      ]
      ++ bodyLines ++ ["  }"]);

  tsKeyTypes = secrets:
    if secrets != []
    then concatMapStringsSep " | " (s: ''"${s.name}"'') secrets
    else "never";

  tsCode = concatStringsSep "\n" ([
      "// Regenerate with: nix run .#generate"
      ""
      "/**"
      " * Server-side environment variables (all secrets)"
      " * Use with: import { serverEnv } from \"./env\";"
      " */"
      "class ServerEnv {"
    ]
    ++ (map tsServerGetter allSecrets)
    ++ [
      "}"
      ""
      "/**"
      " * Client-side environment variables (public only)"
      " * Safe to use in browser code"
      " * Use with: import { clientEnv } from \"./env\";"
      " */"
      "class ClientEnv {"
    ]
    ++ (map tsClientGetter publicSecrets)
    ++ [
      "}"
      ""
      "/** Server environment - all secrets */"
      "export const serverEnv = new ServerEnv();"
      ""
      "/** Client environment - public secrets only */"
      "export const clientEnv = new ClientEnv();"
      ""
      "/** Default export for convenience */"
      "export default serverEnv;"
      ""
      "// Type exports"
      "export type ServerEnvKeys = ${tsKeyTypes allSecrets};"
      "export type ClientEnvKeys = ${tsKeyTypes publicSecrets};"
      ""
    ]);

  # ══════════════════════════════════════════════════════════════════════════════
  # Python Code Generation
  # ══════════════════════════════════════════════════════════════════════════════

  pyServerProp = s: let
    type =
      if s.required
      then "str"
      else "str | None";
    desc =
      if s.description != ""
      then s.description
      else s.name;
    name = lib.toLower s.name;
    bodyLines =
      if s.required
      then [
        ''value = os.environ.get("${s.name}")''
        "        if not value:"
        ''raise ValueError("Missing required env var: ${s.name}")''
        "        return value"
      ]
      else [''return os.environ.get("${s.name}")''];
  in
    concatStringsSep "\n" ([
        ""
        "    @property"
        "    def ${name}(self) -> ${type}:"
        ''"""${desc}"""''
      ]
      ++ bodyLines);

  pyClientProp = s: let
    type =
      if s.required
      then "str"
      else "str | None";
    desc =
      if s.description != ""
      then s.description
      else s.name;
    name = lib.toLower s.name;
    bodyLines =
      if s.required
      then [
        ''value = os.environ.get("PUBLIC_${s.name}")''
        "        if not value:"
        ''raise ValueError("Missing required env var: PUBLIC_${s.name}")''
        "        return value"
      ]
      else [''return os.environ.get("PUBLIC_${s.name}")''];
  in
    concatStringsSep "\n" ([
        ""
        "    @property"
        "    def ${name}(self) -> ${type}:"
        ''"""${desc}"""''
      ]
      ++ bodyLines);

  pyCode = concatStringsSep "\n" ([
      "# Generated by stackpanel - do not edit manually"
      "# Regenerate with: nix run .#generate"
      ""
      "import os"
      ""
      ""
      "class ServerEnv:"
      ''"""Server-side environment variables (all secrets)"""''
    ]
    ++ (map pyServerProp allSecrets)
    ++ [
      ""
      ""
      "class ClientEnv:"
      ''"""Client-side environment variables (public only)"""''
    ]
    ++ (map pyClientProp publicSecrets)
    ++ [
      ""
      ""
      "# Singleton instances"
      "server_env = ServerEnv()"
      "client_env = ClientEnv()"
      ""
      "# Convenience alias"
      "env = server_env"
      ""
    ]);

  # ══════════════════════════════════════════════════════════════════════════════
  # Go Code Generation
  # ══════════════════════════════════════════════════════════════════════════════

  goField = s: let
    type =
      if s.required
      then "string"
      else "*string";
    comment = optionalString (s.description != "") " // ${s.description}";
  in "	${s.name} ${type}${comment}";

  goLoadField = s:
    if s.required
    then
      concatStringsSep "\n" [
        ''if v := os.Getenv("${s.name}"); v != "" {''
        "		env.${s.name} = v"
        "	} else {"
        ''return nil, fmt.Errorf("missing required env var: ${s.name}")''
        "	}"
      ]
    else
      concatStringsSep "\n" [
        ''if v := os.Getenv("${s.name}"); v != "" {''
        "		env.${s.name} = &v"
        "	}"
      ];

  goLoadClientField = s:
    if s.required
    then
      concatStringsSep "\n" [
        ''if v := os.Getenv("PUBLIC_${s.name}"); v != "" {''
        "		env.${s.name} = v"
        "	} else {"
        ''return nil, fmt.Errorf("missing required env var: PUBLIC_${s.name}")''
        "	}"
      ]
    else
      concatStringsSep "\n" [
        ''if v := os.Getenv("PUBLIC_${s.name}"); v != "" {''
        "		env.${s.name} = &v"
        "	}"
      ];

  goCode = concatStringsSep "\n" ([
      "// Generated by stackpanel - do not edit manually"
      "// Regenerate with: nix run .#generate"
      ""
      "package env"
      ""
      "import ("
      ''"fmt"''
      ''"os"''
      ")"
      ""
      "// ServerEnv contains all environment variables (sensitive + public)"
      "type ServerEnv struct {"
    ]
    ++ (map goField allSecrets)
    ++ [
      "}"
      ""
      "// ClientEnv contains only public environment variables"
      "type ClientEnv struct {"
    ]
    ++ (map goField publicSecrets)
    ++ [
      "}"
      ""
      "// LoadServerEnv loads all environment variables"
      "func LoadServerEnv() (*ServerEnv, error) {"
      "	env := &ServerEnv{}"
    ]
    ++ (map goLoadField allSecrets)
    ++ [
      "	return env, nil"
      "}"
      ""
      "// LoadClientEnv loads only public environment variables"
      "func LoadClientEnv() (*ClientEnv, error) {"
      "	env := &ClientEnv{}"
    ]
    ++ (map goLoadClientField publicSecrets)
    ++ [
      "	return env, nil"
      "}"
      ""
      "// MustLoadServerEnv loads server env or panics"
      "func MustLoadServerEnv() *ServerEnv {"
      "	env, err := LoadServerEnv()"
      "	if err != nil {"
      "		panic(err)"
      "	}"
      "	return env"
      "}"
      ""
      "// MustLoadClientEnv loads client env or panics"
      "func MustLoadClientEnv() *ClientEnv {"
      "	env, err := LoadClientEnv()"
      "	if err != nil {"
      "		panic(err)"
      "	}"
      "	return env"
      "}"
      ""
    ]);
in {
  options.stackpanel.secrets = {
    schema = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          required = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether this secret is required (affects nullability in generated code)";
          };
          sensitive = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether this secret is sensitive. Non-sensitive secrets get PUBLIC_ prefix and are safe for client-side code";
          };
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Description of what this secret is for";
          };
        };
      });
      default = {};
      example = lib.literalExpression ''
        {
          DATABASE_URL = { required = true; sensitive = true; description = "PostgreSQL connection string"; };
          STRIPE_SECRET_KEY = { required = true; sensitive = true; };
          STRIPE_PUBLISHABLE_KEY = { required = true; sensitive = false; };  # -> PUBLIC_*
          ANALYTICS_ID = { required = false; sensitive = false; description = "Google Analytics ID"; };
        }
      '';
      description = "Schema defining expected secrets with their properties";
    };

    codegen = {
      enable =
        lib.mkEnableOption "Generate typed env modules"
        // {
          default = cfg.schema != {};
        };

      typescript = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Generate TypeScript env module";
        };
        path = lib.mkOption {
          type = lib.types.str;
          default = "packages/env/src/env.ts";
          description = "Output path for TypeScript module";
        };
      };

      python = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Generate Python env module";
        };
        path = lib.mkOption {
          type = lib.types.str;
          default = "packages/env/env.py";
          description = "Output path for Python module";
        };
      };

      go = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Generate Go env module";
        };
        path = lib.mkOption {
          type = lib.types.str;
          default = "internal/env/env.go";
          description = "Output path for Go module";
        };
      };
    };
  };

  config = lib.mkIf (cfg.enable && cfg.codegen.enable && cfg.schema != {}) {
    stackpanel.files =
      {}
      // lib.optionalAttrs cfg.codegen.typescript.enable {
        ${cfg.codegen.typescript.path} = tsCode;
      }
      // lib.optionalAttrs cfg.codegen.python.enable {
        ${cfg.codegen.python.path} = pyCode;
      }
      // lib.optionalAttrs cfg.codegen.go.enable {
        ${cfg.codegen.go.path} = goCode;
      };
  };
}
