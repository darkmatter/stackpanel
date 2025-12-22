# Codegen configuration for this app
# This file is imported by the Nix module and can be edited by the web UI
{
  codegen = {
    # Language for generated env module
    # Options: "typescript" | "python" | "go" | null (disable)
    language = "typescript";

    # Output path for generated code (relative to repo root)
    path = "packages/api/src/env.ts";
  };
}
