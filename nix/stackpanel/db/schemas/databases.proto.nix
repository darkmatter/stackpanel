# ==============================================================================
# databases.proto.nix
#
# Protobuf schema for database configuration.
# Defines database connection and configuration settings per environment.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "databases.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  enums = {
    DatabaseType = proto.mkEnum {
      name = "DatabaseType";
      description = "Supported database types";
      values = [
        "DATABASE_TYPE_UNSPECIFIED"
        "DATABASE_TYPE_POSTGRESQL"
        "DATABASE_TYPE_MYSQL"
        "DATABASE_TYPE_SQLITE"
        "DATABASE_TYPE_MONGODB"
      ];
    };

    SSLMode = proto.mkEnum {
      name = "SSLMode";
      description = "SSL mode for PostgreSQL connections";
      values = [
        "SSL_MODE_UNSPECIFIED"
        "SSL_MODE_DISABLE"
        "SSL_MODE_ALLOW"
        "SSL_MODE_PREFER"
        "SSL_MODE_REQUIRE"
        "SSL_MODE_VERIFY_CA"
        "SSL_MODE_VERIFY_FULL"
      ];
    };
  };

  messages = {
    # Root databases configuration
    Databases = proto.mkMessage {
      name = "Databases";
      description = "Database connection and configuration settings";
      fields = {
        default = proto.withExample "primary" (proto.string 1 "Default database configuration to use");
        databases = proto.map "string" "DatabaseInstance" 2 "Database configurations by environment/name";
      };
    };

    # Database instance configuration
    DatabaseInstance = proto.mkMessage {
      name = "DatabaseInstance";
      description = "Database instance configuration for a specific environment";
      fields = {
        type = proto.message "DatabaseType" 1 "Database type";
        connection = proto.message "Connection" 2 "Database connection settings";
        pool = proto.message "Pool" 3 "Connection pool settings";
        migrations_path = proto.withExample "./apps/server/migrations" (proto.string 4 "Path to migrations directory");
        seeds_path = proto.optional (proto.withExample "./apps/server/seeds" (proto.string 5 "Path to seed data directory"));
        auto_migrate = proto.withExample true (proto.bool 6 "Run migrations on startup");
      };
    };

    # Connection settings
    Connection = proto.mkMessage {
      name = "Connection";
      description = "Database connection settings";
      fields = {
        host = proto.withExample "localhost" (proto.string 1 "Database host");
        port = proto.withExample 5432 (proto.int32 2 "Database port");
        database = proto.withExample "stackpanel" (proto.string 3 "Database name");
        username = proto.withExample "postgres" (proto.string 4 "Database username");
        password_env = proto.optional (proto.withExample "DATABASE_PASSWORD" (proto.string 5 "Environment variable containing the password"));
        ssl = proto.withExample false (proto.bool 6 "Enable SSL/TLS connection");
        ssl_mode = proto.message "SSLMode" 7 "SSL mode for PostgreSQL connections";
      };
    };

    # Pool settings
    Pool = proto.mkMessage {
      name = "Pool";
      description = "Connection pool settings";
      fields = {
        min = proto.withExample 2 (proto.int32 1 "Minimum connections in pool");
        max = proto.withExample 10 (proto.int32 2 "Maximum connections in pool");
        idle_timeout = proto.withExample 30 (proto.int32 3 "Idle connection timeout in seconds");
        connection_timeout = proto.withExample 5 (proto.int32 4 "Connection timeout in seconds");
      };
    };
  };
}
