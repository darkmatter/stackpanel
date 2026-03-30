# ==============================================================================
# nix/hosts/vms/api.nix — API VM guest configuration
#
# Runs the Stackpanel API service (Bun + apps/api/src/index.ts).
# Resources: 4 vCPUs, 8192 MB RAM, 20 GB disk  (configured by the host mkVM).
#
# Deployment: the stackpanel source tree is expected at /opt/stackpanel/
# (populated via a deployment step, CI/CD push, or virtiofs source share).
#
# Exposed port: 3000  (TCP, internal bridge only)
# ==============================================================================
{ pkgs, lib, config, ... }:
{
  environment.systemPackages = with pkgs; [
    bun
    nodejs
  ];

  # --- System user for the API service ---
  users.users.api = {
    isSystemUser = true;
    group = "api";
    home = "/opt/stackpanel";
    createHome = false;
  };
  users.groups.api = { };

  # Ensure working directories exist with correct ownership
  systemd.tmpfiles.rules = [
    "d /opt/stackpanel 0755 api api -"
    "d /opt/stackpanel/apps/api 0755 api api -"
  ];

  # --- Stackpanel API systemd service ---
  systemd.services.stackpanel-api = {
    description = "Stackpanel API (Bun / Hono)";
    documentation = [ "https://github.com/darkmatter/stackpanel" ];
    after = [
      "network.target"
      "tailscaled.service"
    ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      NODE_ENV = "production";
      PORT = "3000";
    };

    serviceConfig = {
      Type = "simple";
      User = "api";
      Group = "api";
      WorkingDirectory = "/opt/stackpanel/apps/api";
      ExecStart = "${pkgs.bun}/bin/bun run /opt/stackpanel/apps/api/src/index.ts";
      Restart = "on-failure";
      RestartSec = "5s";
      StandardOutput = "journal";
      StandardError = "journal";
      # Basic hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/opt/stackpanel" ];
    };
  };

  # Open port 3000 (already configured by host mkVM extraPorts — this is belt+suspenders)
  networking.firewall.allowedTCPPorts = [ 3000 ];
}
