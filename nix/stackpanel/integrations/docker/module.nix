# ==============================================================================
# module.nix - Container Tooling Module
#
# Provides container-related tools (skopeo) and image reference computation
# for working with OCI container images.
#
# For container BUILDING, use the containers module instead:
#   stackpanel.containers.settings.backend = "nix2container"; # or "dockerTools"
#   stackpanel.apps.web.container.enable = true;
#
# This module provides:
#   - skopeo for image inspection, copying, and registry operations
#   - Image reference computation (registry/name:tag)
#   - Helper scripts for common image operations
#
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;
  dockerCfg = cfg.docker;

  # ---------------------------------------------------------------------------
  # Compute full image reference: registry/name:tag
  # ---------------------------------------------------------------------------
  mkImageRef =
    _key: imgCfg:
    let
      base = if imgCfg.registry != null then "${imgCfg.registry}/${imgCfg.name}" else imgCfg.name;
    in
    "${base}:${imgCfg.tag}";

in
{
  # ===========================================================================
  # Options
  # ===========================================================================
  options.stackpanel.docker = {
    enable = lib.mkEnableOption "container tooling (skopeo for OCI image operations)";

    images = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "Image name (e.g., 'my-web-app').";
              };

              tag = lib.mkOption {
                type = lib.types.str;
                default = "latest";
                description = "Image tag.";
              };

              registry = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Registry URL (e.g., 'registry.fly.io', 'ghcr.io/org').";
                example = "registry.fly.io";
              };
            };
          }
        )
      );
      default = { };
      description = ''
        Image reference definitions for computing full image refs.
        For container building, use stackpanel.containers instead.
      '';
    };

    # Read-only computed outputs
    imagesComputed = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = { };
      description = "Computed full image references (registry/name:tag).";
    };
  };

  # ===========================================================================
  # Configuration
  # ===========================================================================
  config = lib.mkIf (cfg.enable && dockerCfg.enable) {
    # Computed outputs
    stackpanel.docker.imagesComputed = lib.mapAttrs mkImageRef dockerCfg.images;

    # Devshell packages
    stackpanel.devshell.packages = [
      pkgs.skopeo
    ];

    # Helper scripts
    stackpanel.scripts = {
      image-inspect = {
        description = "Inspect a container image";
        args = [
          {
            name = "image-ref";
            description = "Image reference (e.g., docker://registry.fly.io/my-app:latest)";
            required = true;
          }
        ];
        exec = ''
          if [ $# -eq 0 ]; then
            echo "Usage: image-inspect <image-ref>"
            echo ""
            echo "Examples:"
            echo "  image-inspect docker://registry.fly.io/my-app:latest"
            echo "  image-inspect docker-daemon:my-app:latest"
            exit 1
          fi
          skopeo inspect "$1"
        '';
      };

      image-copy = {
        description = "Copy an image between registries";
        args = [
          {
            name = "source";
            description = "Source image reference";
            required = true;
          }
          {
            name = "destination";
            description = "Destination image reference";
            required = true;
          }
        ];
        exec = ''
          if [ $# -lt 2 ]; then
            echo "Usage: image-copy <source> <destination>"
            echo ""
            echo "Examples:"
            echo "  image-copy docker-daemon:my-app:latest docker://registry.fly.io/my-app:latest"
            echo "  image-copy docker://ghcr.io/org/app:v1 docker://registry.fly.io/app:v1"
            exit 1
          fi
          skopeo copy --insecure-policy "$1" "$2"
        '';
      };

      image-list-tags = {
        description = "List tags for an image in a registry";
        args = [
          {
            name = "image-name";
            description = "Image name in registry (e.g., docker://registry.fly.io/my-app)";
            required = true;
          }
        ];
        exec = ''
          if [ $# -eq 0 ]; then
            echo "Usage: image-list-tags <image-name>"
            echo ""
            echo "Examples:"
            echo "  image-list-tags docker://registry.fly.io/my-app"
            echo "  image-list-tags docker://ghcr.io/org/app"
            exit 1
          fi
          skopeo list-tags "$1"
        '';
      };

      image-delete = {
        description = "Delete an image from a registry";
        args = [
          {
            name = "image-ref";
            description = "Image reference to delete";
            required = true;
          }
        ];
        exec = ''
          if [ $# -eq 0 ]; then
            echo "Usage: image-delete <image-ref>"
            echo ""
            echo "Examples:"
            echo "  image-delete docker://registry.fly.io/my-app:old-tag"
            exit 1
          fi
          skopeo delete "$1"
        '';
      };
    };

    # Health checks
    stackpanel.healthchecks.modules.${meta.id} = {
      enable = true;
      displayName = meta.name;
      checks = {
        skopeo-installed = {
          description = "Skopeo is installed for OCI image operations";
          script = ''
            command -v skopeo >/dev/null 2>&1 && skopeo --version
          '';
          severity = "critical";
          timeout = 5;
        };
      };
    };

    # Module registration
    stackpanel.modules.${meta.id} = {
      enable = true;
      meta = {
        name = meta.name;
        description = meta.description;
        icon = meta.icon;
        category = meta.category;
        author = meta.author;
        version = meta.version;
        homepage = meta.homepage;
      };
      source.type = "builtin";
      features = meta.features;
      tags = meta.tags;
      priority = meta.priority;
    };
  };
}
