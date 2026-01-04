# ==============================================================================
# services.proto.nix
#
# Protobuf schema for global development services configuration.
# Defines configuration for PostgreSQL, Redis, Minio, and Caddy.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "services.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  messages = {
    # Root services configuration
    Services = proto.mkMessage {
      name = "Services";
      description = "Global development services configuration";
      fields = {
        project_name = proto.string 1 "Project name for database/site registration";
        postgres = proto.message "Postgres" 2 "PostgreSQL service configuration";
        redis = proto.message "Redis" 3 "Redis service configuration";
        minio = proto.message "Minio" 4 "Minio S3-compatible service configuration";
        caddy = proto.message "Caddy" 5 "Caddy reverse proxy configuration";
      };
    };

    # PostgreSQL service configuration
    Postgres = proto.mkMessage {
      name = "Postgres";
      description = "PostgreSQL service configuration";
      fields = {
        enable = proto.bool 1 "Enable PostgreSQL service";
        databases = proto.repeated (proto.string 2 "List of databases to create for this project");
        port = proto.optional (
          proto.int32 3 "PostgreSQL port. If not set, uses computed port from stackpanel.ports"
        );
        version = proto.string 4 "PostgreSQL version (e.g., '15', '16', '17')";
        extensions = proto.repeated (proto.string 5 "PostgreSQL extensions to enable");
      };
    };

    # Redis service configuration
    Redis = proto.mkMessage {
      name = "Redis";
      description = "Redis service configuration";
      fields = {
        enable = proto.bool 1 "Enable Redis service";
        port = proto.optional (
          proto.int32 2 "Redis port. If not set, uses computed port from stackpanel.ports"
        );
        maxmemory = proto.string 3 "Maximum memory limit for Redis";
        maxmemory_policy = proto.string 4 "Eviction policy when maxmemory is reached";
      };
    };

    # Minio S3-compatible service configuration
    Minio = proto.mkMessage {
      name = "Minio";
      description = "Minio S3-compatible service configuration";
      fields = {
        enable = proto.bool 1 "Enable Minio (S3-compatible) service";
        port = proto.optional (
          proto.int32 2 "Minio API port. If not set, uses computed port from stackpanel.ports"
        );
        console_port = proto.optional (
          proto.int32 3 "Minio console port. If not set, uses computed port from stackpanel.ports"
        );
        buckets = proto.repeated (proto.string 4 "Buckets to create on startup");
      };
    };

    # Caddy reverse proxy configuration
    Caddy = proto.mkMessage {
      name = "Caddy";
      description = "Caddy reverse proxy configuration";
      fields = {
        enable = proto.bool 1 "Enable Caddy reverse proxy";
        sites = proto.map "string" "CaddySite" 2 "Sites to register with Caddy (domain -> config)";
      };
    };

    # Caddy site configuration
    CaddySite = proto.mkMessage {
      name = "CaddySite";
      description = "Caddy site configuration";
      fields = {
        upstream = proto.string 1 "Upstream address (e.g., 'localhost:3000')";
        tls = proto.bool 2 "Enable TLS for this site";
      };
    };
  };
}
