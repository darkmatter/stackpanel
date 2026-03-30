# ==============================================================================
# nix/hosts/vms/common.nix — Common microVM guest configuration
#
# Imported by every VM role.  Provides Tailscale, SSH, basic packages, and Nix
# settings that every guest needs.
#
# Expects `vmName` in specialArgs (set by the host's mkVM helper).
# ==============================================================================
{ pkgs, lib, config, vmName, ... }:
{
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    jq
    curl
    tmux
    ripgrep
    tree
  ];

  # Tailscale — auth key sourced from the virtiofs-shared secrets dir
  services.tailscale = {
    enable = true;
    authKeyFile = "/run/vm-secrets/tailscale-auth-key";
    extraUpFlags = [
      "--hostname=${vmName}"
      "--accept-routes"
    ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" ];
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  system.stateVersion = "24.11";
}
