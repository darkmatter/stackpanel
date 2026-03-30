# ==============================================================================
# nix/hosts/vms/db.nix — DB VM guest configuration
#
# Runs PostgreSQL 17 + Redis for Stackpanel.
# Resources: 8 vCPUs, 8192 MB RAM, 61440 MB (60 GB) disk  (by host mkVM).
#
# Exposed ports: 5432 (PostgreSQL), 6379 (Redis) — internal bridge only.
# Both services listen on 0.0.0.0; access control is at the bridge/firewall
# level (10.0.100.0/24 is trusted by the host).
# ==============================================================================
{ pkgs, lib, config, ... }:
{
  # --- PostgreSQL 17 ---
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;

    # Basic performance tuning for an 8 GB RAM VM
    settings = {
      max_connections = 100;
      shared_buffers = "2GB";
      effective_cache_size = "5GB";
      maintenance_work_mem = "512MB";
      checkpoint_completion_target = "0.9";
      wal_buffers = "16MB";
      default_statistics_target = 100;
      work_mem = "20MB";
    };

    # Allow connections from bridge subnet with SCRAM auth;
    # localhost uses trust (internal systemd services only)
    authentication = lib.mkOverride 10 ''
      # TYPE   DATABASE  USER  ADDRESS           METHOD
      local    all       all                     trust
      host     all       all   127.0.0.1/32      trust
      host     all       all   10.0.100.0/24     scram-sha-256
    '';

    initialDatabases = [
      { name = "stackpanel"; }
    ];
  };

  # Open PostgreSQL to the bridge (the host firewall trusts br-vms)
  networking.firewall.allowedTCPPorts = [ 5432 6379 ];

  # --- Redis ---
  services.redis.servers.default = {
    enable = true;
    # Listen on all interfaces (access restricted at bridge/firewall level)
    bind = "0.0.0.0";
    port = 6379;
    settings = {
      # Memory management: evict LRU keys when full
      maxmemory = "1500mb";
      "maxmemory-policy" = "allkeys-lru";
      # Persistence: RDB snapshots + AOF for durability
      save = "900 1 300 10 60 10000";
      appendonly = "yes";
      appendfsync = "everysec";
    };
  };

  environment.systemPackages = with pkgs; [
    postgresql_17
    redis
  ];
}
