# ==============================================================================
# nix/hosts/hzcloud-hel-1/default.nix — NixOS host config for hzcloud-hel-1
#
# Hetzner Cloud Helsinki (to be provisioned — pending IP assignment).
# Runs microVMs (api, db) via cloud-hypervisor + microvm.nix.
#
# Network topology:
#   eth0 (public, Hetzner DHCP / static)
#   └─ br-vms  10.0.100.1/24  — bridge for VM TAP interfaces
#       ├─ vm-api  10.0.100.11   (api VM)
#       └─ vm-db   10.0.100.12   (db VM)
#
# NAT: br-vms → eth0 (VMs reach internet via host)
#
# Assumptions:
#   - External interface is eth0 (Hetzner Cloud VPS standard).
#     Update `externalInterface` below if the provisioned server uses a
#     different name (verify with `ip link` after first boot).
#   - IP: currently "provisioning-pending" — update deployment.machines.
#     hzcloud-hel-1.host in .stack/config.nix when the server is provisioned.
#
# Usage: add this path to deployment.machines.hzcloud-hel-1.modules in config.nix
# ==============================================================================
{ config, pkgs, lib, inputs, ... }:
let
  # SSH keys authorized on every VM guest
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA+M/DHDlKgayM6wsiX6r704pE+2qENOsKcytC7sBhKA"
  ];

  # Host external interface (Hetzner Cloud VPS standard naming)
  externalInterface = "eth0";

  # VM definitions managed by this host
  vmNames = [ "api" "db" ];

  # ---------------------------------------------------------------------------
  # mkVM — build a microvm.nix VM definition (identical helper to ovh-usw-1)
  # ---------------------------------------------------------------------------
  mkVM =
    {
      name,
      id,
      vcpu,
      mem,
      diskSize,
      extraPorts ? [ ],
      extraImports ? [ ],
    }:
    {
      inherit pkgs;
      specialArgs = {
        inherit inputs;
        vmName = name;
      };
      config = {
        imports = [
          ../vms/common.nix
        ] ++ extraImports;

        networking = {
          hostName = name;
          useNetworkd = true;
          useDHCP = false;
          firewall.allowedTCPPorts = [ 22 ] ++ extraPorts;
        };

        # Static IP via systemd-networkd
        systemd.network = {
          enable = true;
          networks."10-vm" = {
            matchConfig.Driver = "virtio_net";
            networkConfig = {
              Address = "10.0.100.${toString (10 + id)}/24";
              Gateway = "10.0.100.1";
              DNS = [ "1.1.1.1" "8.8.8.8" ];
              DHCP = "no";
            };
          };
        };

        microvm = {
          hypervisor = "cloud-hypervisor";
          inherit vcpu mem;

          vsock.cid = 100 + id;

          shares = [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              proto = "virtiofs";
            }
            {
              tag = "vm-secrets";
              source = "/var/lib/vm-secrets";
              mountPoint = "/run/vm-secrets";
              proto = "virtiofs";
            }
          ];

          volumes = [
            {
              mountPoint = "/";
              image = "/var/lib/microvms/${name}/root.img";
              size = diskSize;
            }
          ];

          interfaces = [
            {
              type = "tap";
              id = "vm-${name}";
              mac = "02:00:00:00:00:0${toString id}";
            }
          ];
        };

        users.users.root.openssh.authorizedKeys.keys = sshKeys;
      };
    };
in
{
  imports = [
    # microvm.nix host module: provides microvm.vms option + TAP management
    inputs.microvm.nixosModules.host
  ];

  # ---------------------------------------------------------------------------
  # Bridge networking for VM TAP interfaces
  # ---------------------------------------------------------------------------
  networking = {
    bridges.br-vms.interfaces = [ ];

    interfaces.br-vms.ipv4.addresses = [
      {
        address = "10.0.100.1";
        prefixLength = 24;
      }
    ];

    firewall = {
      trustedInterfaces = [ "tailscale0" "br-vms" ];
      # Open 80 (ACME HTTP challenge) and 443 (HTTPS) for Caddy on the host
      allowedTCPPorts = [ 80 443 ];
    };

    # NAT: VMs reach the internet through the host's public interface
    nat = {
      enable = true;
      internalInterfaces = [ "br-vms" ];
      externalInterface = externalInterface;
    };
  };

  # ---------------------------------------------------------------------------
  # Tailscale on the host
  # ---------------------------------------------------------------------------
  services.tailscale = {
    enable = true;
    # authKeyFile: must be provisioned via agenix/SOPS before first deploy.
    authKeyFile = "/run/secrets/tailscale-auth-key";
    extraUpFlags = [
      "--hostname=hzcloud-hel-1"
      "--accept-routes"
    ];
  };

  # ---------------------------------------------------------------------------
  # dnsmasq: DHCP + DNS served on the VM bridge
  # ---------------------------------------------------------------------------
  services.dnsmasq = {
    enable = true;
    settings = {
      interface = "br-vms";
      bind-interfaces = true;
      dhcp-range = [ "10.0.100.10,10.0.100.50,24h" ];
      dhcp-option = [ "option:router,10.0.100.1" ];
    };
  };

  # ---------------------------------------------------------------------------
  # Caddy: TLS termination on the host, reverse-proxying to the API VM
  #
  # Caddy uses ACME (Let's Encrypt) auto-HTTPS by default.
  # Port 80 must be open externally for the HTTP-01 challenge.
  # ---------------------------------------------------------------------------
  services.caddy = {
    enable = true;
    virtualHosts."api.stackpanel.com" = {
      extraConfig = ''
        reverse_proxy 10.0.100.11:3000
      '';
    };
  };

  # ---------------------------------------------------------------------------
  # microVM definitions
  # ---------------------------------------------------------------------------
  microvm.vms = {
    api = mkVM {
      name = "api";
      id = 1;
      vcpu = 4;
      mem = 8192; # 8 GB
      diskSize = 20480; # 20 GB
      extraPorts = [ 3000 ];
      extraImports = [ ../vms/api.nix ];
    };

    db = mkVM {
      name = "db";
      id = 2;
      vcpu = 8;
      mem = 8192; # 8 GB
      diskSize = 61440; # 60 GB
      extraPorts = [ 5432 6379 ];
      extraImports = [ ../vms/db.nix ];
    };
  };

  # ---------------------------------------------------------------------------
  # Systemd services: bridge TAP interfaces + populate VM secrets
  # ---------------------------------------------------------------------------
  systemd.services =
    {
      vm-secrets = {
        description = "Populate shared VM secrets directory";
        after = [ "network.target" ];
        before = map (n: "microvm@${n}.service") vmNames;
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          mkdir -p /var/lib/vm-secrets
          chmod 700 /var/lib/vm-secrets
          if [ -f /run/secrets/tailscale-auth-key ]; then
            install -m 600 \
              /run/secrets/tailscale-auth-key \
              /var/lib/vm-secrets/tailscale-auth-key
          fi
        '';
      };
    }
    // builtins.listToAttrs (
      map (name: {
        name = "microvm-bridge-${name}";
        value = {
          description = "Bridge vm-${name} TAP interface to br-vms";
          after = [
            "microvm-tap-interfaces@${name}.service"
            "br-vms-netdev.service"
            "network-addresses-br-vms.service"
          ];
          requires = [ "microvm-tap-interfaces@${name}.service" ];
          before = [ "microvm@${name}.service" ];
          partOf = [ "microvm@${name}.service" ];
          wantedBy = [ "microvms.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.iproute2}/bin/ip link set vm-${name} master br-vms";
          };
        };
      }) vmNames
    );
}
