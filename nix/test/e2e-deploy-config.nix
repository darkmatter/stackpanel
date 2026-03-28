# ==============================================================================
# e2e-deploy-config.nix — Minimal NixOS configuration for E2E deploy tests
#
# Used by: nixosConfigurations.e2e-test (added in flake.nix)
#
# Imports amazon-image.nix for EC2 compatibility (virtio, cloud-init, etc.)
# and runs nginx with a health endpoint on port 8080 so the test can verify
# that a NixOS deploy succeeded.
#
# This config is ALWAYS present in the flake but only used for testing.
# ==============================================================================
{
  modulesPath,
  lib,
  pkgs,
  ...
}:
{
  imports = [ "${modulesPath}/virtualisation/amazon-image.nix" ];

  services.nginx = {
    enable = true;
    virtualHosts.default = {
      default = true;
      listen = [
        {
          port = 8080;
          addr = "0.0.0.0";
        }
      ];
      locations."/health" = {
        return = "200 'e2e-deploy-ok'";
        extraConfig = ''
          default_type text/plain;
        '';
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    22
    8080
  ];
  services.openssh.enable = lib.mkDefault true;
  system.stateVersion = "24.11";
}
