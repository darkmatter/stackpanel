{
  lib ? import <nixpkgs/lib>,
}:
let
  # Helper to create an env var definition
  mkEnvVar =
    {
      name,
      description,
      category,
      source ? "nix",
      required ? false,
      default ? null,
      example ? null,
      deprecated ? false,
      deprecationMessage ? null,
      goField ? null, # Corresponding Go struct field name
    }:
    {
      inherit
        name
        description
        category
        source
        required
        default
        example
        deprecated
        deprecationMessage
        goField
        ;
    };

  # Categories for organizing variables
  categories = {
    core = "Core Stackpanel";
    paths = "Paths & Directories";
    agent = "Stackpanel Agent";
    stepca = "Step CA (Certificates)";
    aws = "AWS & Roles Anywhere";
    minio = "MinIO (S3-Compatible Storage)";
    services = "Services Config";
    devenv = "Devenv Integration";
    ide = "IDE Integration";
  };
in
{
  inherit mkEnvVar categories;
}
