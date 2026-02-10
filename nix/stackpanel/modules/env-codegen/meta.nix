# Module metadata for fast discovery (without full evaluation)
{
  id = "env-codegen";
  name = "Environment Codegen";
  description = "Generates packages/gen/env structure from app configurations";
  icon = "FileCode";
  category = "development";
  author = "stackpanel";
  version = "1.0.0";
  homepage = "https://stackpanel.dev/docs/env-codegen";
  features = [
    "sops-config-generation"
    "typescript-codegen"
    "entrypoint-generation"
  ];
  tags = [
    "codegen"
    "secrets"
    "env"
    "typescript"
  ];
  priority = 50;
}
