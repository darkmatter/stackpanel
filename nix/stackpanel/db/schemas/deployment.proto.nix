# ==============================================================================
# deployment.proto.nix
#
# Protobuf schema for deployment configuration.
# Defines deployment providers, targets, and per-app deployment settings.
#
# Supported providers:
#   - Cloudflare Workers (edge, serverless)
#   - Fly.io (containers, VMs)
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "deployment.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------
  enums = {
    DeploymentProvider = proto.mkEnum {
      name = "DeploymentProvider";
      description = "Deployment provider/platform";
      values = [
        "DEPLOYMENT_PROVIDER_UNSPECIFIED"
        "DEPLOYMENT_PROVIDER_CLOUDFLARE"
        "DEPLOYMENT_PROVIDER_FLY"
        "DEPLOYMENT_PROVIDER_AWS_ECS"
        "DEPLOYMENT_PROVIDER_RAILWAY"
        "DEPLOYMENT_PROVIDER_RENDER"
      ];
    };

    DeploymentStatus = proto.mkEnum {
      name = "DeploymentStatus";
      description = "Current status of a deployment";
      values = [
        "DEPLOYMENT_STATUS_UNSPECIFIED"
        "DEPLOYMENT_STATUS_PENDING"
        "DEPLOYMENT_STATUS_BUILDING"
        "DEPLOYMENT_STATUS_DEPLOYING"
        "DEPLOYMENT_STATUS_DEPLOYED"
        "DEPLOYMENT_STATUS_FAILED"
        "DEPLOYMENT_STATUS_ROLLED_BACK"
      ];
    };

    CloudflareWorkerType = proto.mkEnum {
      name = "CloudflareWorkerType";
      description = "Type of Cloudflare Worker deployment";
      values = [
        "CLOUDFLARE_WORKER_TYPE_UNSPECIFIED"
        "CLOUDFLARE_WORKER_TYPE_VITE"
        "CLOUDFLARE_WORKER_TYPE_WORKER"
        "CLOUDFLARE_WORKER_TYPE_PAGES"
      ];
    };

    FlyMachineCpuKind = proto.mkEnum {
      name = "FlyMachineCpuKind";
      description = "Fly.io machine CPU type";
      values = [
        "FLY_MACHINE_CPU_KIND_UNSPECIFIED"
        "FLY_MACHINE_CPU_KIND_SHARED"
        "FLY_MACHINE_CPU_KIND_PERFORMANCE"
      ];
    };

    FlyAutoStop = proto.mkEnum {
      name = "FlyAutoStop";
      description = "Fly.io auto-stop behavior";
      values = [
        "FLY_AUTO_STOP_UNSPECIFIED"
        "FLY_AUTO_STOP_OFF"
        "FLY_AUTO_STOP_STOP"
        "FLY_AUTO_STOP_SUSPEND"
      ];
    };
  };

  # ---------------------------------------------------------------------------
  # Messages
  # ---------------------------------------------------------------------------
  messages = {
    # Root deployment configuration
    Deployment = proto.mkMessage {
      name = "Deployment";
      description = "Global deployment configuration";
      fields = {
        default_provider = proto.message "DeploymentProvider" 1 "Default provider for all apps";
        fly = proto.message "FlyGlobalConfig" 2 "Fly.io global settings";
        cloudflare = proto.message "CloudflareGlobalConfig" 3 "Cloudflare global settings";
      };
    };

    # -------------------------------------------------------------------------
    # Fly.io Configuration
    # -------------------------------------------------------------------------
    FlyGlobalConfig = proto.mkMessage {
      name = "FlyGlobalConfig";
      description = "Fly.io global settings";
      fields = {
        organization = proto.optional (proto.withExample "darkmatter-io" (proto.string 1 "Fly.io organization name"));
        default_region = proto.withExample "iad" (proto.string 2 "Default region for new apps");
        registry_prefix = proto.withExample "registry.fly.io/darkmatter" (proto.string 3 "Container registry prefix");
      };
    };

    FlyAppConfig = proto.mkMessage {
      name = "FlyAppConfig";
      description = "Fly.io per-app deployment configuration";
      fields = {
        app_name = proto.withExample "stackpanel-web" (proto.string 1 "Fly.io app name");
        region = proto.withExample "iad" (proto.string 2 "Primary deployment region");
        memory = proto.withExample "512mb" (proto.string 3 "Memory allocation (e.g., '512mb', '1gb')");
        cpu_kind = proto.message "FlyMachineCpuKind" 4 "CPU type";
        cpus = proto.withExample 1 (proto.int32 5 "Number of CPUs");
        auto_stop = proto.message "FlyAutoStop" 6 "Auto-stop behavior";
        auto_start = proto.withExample true (proto.bool 7 "Auto-start on request");
        min_machines = proto.withExample 0 (proto.int32 8 "Minimum machines to keep running");
        force_https = proto.withExample true (proto.bool 9 "Force HTTPS for all requests");
        env = proto.map "string" "string" 10 "Environment variables";
        secrets = proto.repeated (proto.withExample "DATABASE_URL" (proto.string 11 "Secret names to inject"));
        health_check_path = proto.optional (proto.withExample "/health" (proto.string 12 "Health check endpoint path"));
        health_check_interval = proto.optional (proto.withExample "30s" (proto.string 13 "Health check interval"));
      };
    };

    # -------------------------------------------------------------------------
    # Cloudflare Configuration
    # -------------------------------------------------------------------------
    CloudflareGlobalConfig = proto.mkMessage {
      name = "CloudflareGlobalConfig";
      description = "Cloudflare global settings";
      fields = {
        account_id = proto.optional (proto.withExample "abcd1234abcd1234abcd1234abcd1234" (proto.string 1 "Cloudflare account ID"));
        compatibility_date = proto.withExample "2026-04-01" (proto.string 2 "Workers compatibility date");
        default_route = proto.optional (proto.withExample "*.stackpanel.com/*" (proto.string 3 "Default custom domain route pattern"));
      };
    };

    CloudflareAppConfig = proto.mkMessage {
      name = "CloudflareAppConfig";
      description = "Cloudflare per-app deployment configuration";
      fields = {
        worker_name = proto.withExample "stackpanel-web" (proto.string 1 "Worker name");
        type = proto.message "CloudflareWorkerType" 2 "Deployment type (vite/worker/pages)";
        route = proto.optional (proto.withExample "stackpanel.com/*" (proto.string 3 "Custom domain route pattern"));
        compatibility = proto.withExample "node" (proto.string 4 "Compatibility mode (node/browser)");
        bindings = proto.map "string" "string" 5 "Environment variable bindings";
        secrets = proto.repeated (proto.withExample "API_KEY" (proto.string 6 "Secret names to inject"));
        kv_namespaces = proto.repeated (proto.withExample "SESSIONS" (proto.string 7 "KV namespace bindings"));
        d1_databases = proto.repeated (proto.withExample "DB" (proto.string 8 "D1 database bindings"));
        r2_buckets = proto.repeated (proto.withExample "ASSETS" (proto.string 9 "R2 bucket bindings"));
      };
    };

    # -------------------------------------------------------------------------
    # Per-App Deployment Config (unified)
    # -------------------------------------------------------------------------
    AppDeployment = proto.mkMessage {
      name = "AppDeployment";
      description = "Per-app deployment configuration";
      fields = {
        enable = proto.withExample true (proto.bool 1 "Enable deployment for this app");
        provider = proto.message "DeploymentProvider" 2 "Deployment provider";
        fly = proto.optional (proto.message "FlyAppConfig" 3 "Fly.io specific config");
        cloudflare = proto.optional (proto.message "CloudflareAppConfig" 4 "Cloudflare specific config");
      };
    };

    # -------------------------------------------------------------------------
    # Deployment History/Status
    # -------------------------------------------------------------------------
    DeploymentRecord = proto.mkMessage {
      name = "DeploymentRecord";
      description = "Record of a deployment";
      fields = {
        id = proto.withExample "deploy-2026-04-30-001" (proto.string 1 "Unique deployment ID");
        app_name = proto.withExample "web" (proto.string 2 "App that was deployed");
        provider = proto.message "DeploymentProvider" 3 "Provider used";
        status = proto.message "DeploymentStatus" 4 "Current status";
        version = proto.withExample "v1.4.2" (proto.string 5 "Version/tag deployed");
        started_at = proto.withExample "2026-04-30T18:21:04Z" (proto.string 6 "ISO timestamp of deployment start");
        completed_at = proto.optional (proto.withExample "2026-04-30T18:23:51Z" (proto.string 7 "ISO timestamp of completion"));
        error = proto.optional (proto.withExample "build failed: missing DATABASE_URL" (proto.string 8 "Error message if failed"));
        url = proto.optional (proto.withExample "https://stackpanel.com" (proto.string 9 "Deployed URL"));
        commit_sha = proto.optional (proto.withExample "ba6e3d245" (proto.string 10 "Git commit SHA"));
        triggered_by = proto.optional (proto.withExample "cooper@darkmatter.io" (proto.string 11 "User or system that triggered"));
      };
    };

    DeploymentHistory = proto.mkMessage {
      name = "DeploymentHistory";
      description = "Collection of deployment records";
      fields = {
        deployments = proto.repeated (proto.message "DeploymentRecord" 1 "List of deployments");
      };
    };
  };
}
