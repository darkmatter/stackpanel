# ==============================================================================
# nix/hosts/ovh-usw-1/default.nix — NixOS host config for ovh-usw-1
#
# OVH US-West bare-metal server (AMD EPYC, 2× 894 GB NVMe).
# Runs microVMs (api, db) via cloud-hypervisor + microvm.nix.
#
# Network topology:
#   ens3f0np0 (public, DHCP)
#   └─ br-vms  10.0.100.1/24  — bridge for VM TAP interfaces
#       ├─ vm-api  10.0.100.11   (api VM)
#       └─ vm-db   10.0.100.12   (db VM)
#
# NAT: br-vms → ens3f0np0 (VMs reach internet via host)
#
# Usage: add this path to deployment.machines.ovh-usw-1.modules in config.nix
# ==============================================================================
{ config, pkgs, lib, inputs, ... }:
let
  # SSH keys authorized on every VM guest
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA+M/DHDlKgayM6wsiX6r704pE+2qENOsKcytC7sBhKA"
  ];

  # Host external interface (OVH bare-metal naming)
  externalInterface = "ens3f0np0";

  # VM definitions managed by this host
  vmNames = [ "api" "db" ];

  # ---------------------------------------------------------------------------
  # mkVM — build a microvm.nix VM definition
  #
  # Parameters:
  #   name        — VM hostname and systemd unit name
  #   id          — integer (1-based); determines IP (10.0.100.10+id) and
  #                 vsockCID (100+id) and TAP MAC suffix
  #   vcpu        — virtual CPUs
  #   mem         — RAM in MB
  #   diskSize    — root volume in MB
  #   extraPorts  — extra TCP ports opened in the guest firewall
  #   extraImports — extra NixOS module paths imported into the guest
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

        # Static IP via systemd-networkd (no DHCP needed)
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
            # /nix/store shared read-only from host (no duplication)
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              proto = "virtiofs";
            }
            # Secrets dir populated by the vm-secrets systemd service
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
    # Empty bridge — TAP interfaces are added dynamically by systemd services
    bridges.br-vms.interfaces = [ ];

    interfaces.br-vms.ipv4.addresses = [
      {
        address = "10.0.100.1";
        prefixLength = 24;
      }
    ];

    firewall = {
      # Trust the VM bridge and Tailscale (inter-VM traffic unrestricted)
      trustedInterfaces = [ "tailscale0" "br-vms" ];
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
    # Example: agenix secret at .stack/secrets/machines/ovh-usw-1/tailscale-auth-key
    authKeyFile = "/run/secrets/tailscale-auth-key";
    extraUpFlags = [
      "--hostname=ovh-usw-1"
      "--accept-routes"
    ];
  };

  # ---------------------------------------------------------------------------
  # dnsmasq: DHCP + DNS served on the VM bridge
  # VMs use static IPs but dnsmasq provides DNS forwarding for guests
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
      # Populate /var/lib/vm-secrets before VMs start.
      # Source: tailscale auth key from secrets manager (agenix/SOPS).
      # Adjust the source path to match your secrets setup.
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
    # Create one bridge-TAP service per VM, following the microvm.nix pattern
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
