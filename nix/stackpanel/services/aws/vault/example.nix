                     # ==============================================================================
# AWS Vault Example Configuration
#
# This file demonstrates various ways to configure AWS Vault with Stackpanel,
# including single profile, multi-profile with fallback, and team workflows.
# ==============================================================================
{
  # ============================================================================
  # Example 1: Basic Single Profile
  # ============================================================================

  # Simplest setup - use one AWS profile with aws-vault
  basic = {
    stackpanel.aws-vault = {
      enable = true;
      profile = "mycompany-dev";
      awscliWrapper.enable = true;
    };
  };

  # ============================================================================
  # Example 2: Multi-Profile with Fallback
  # ============================================================================

  # Try multiple profiles in order until one succeeds
  # Useful when team members have different access levels
  multiProfile = {
    stackpanel.aws-vault = {
      enable = true;
      profile = "production";  # Default/primary profile

      # Try these in order: prod → staging → readonly
      profiles = [
        "production"
        "staging"
        "readonly"
      ];

      # Enable wrappers so aws/terraform automatically use aws-vault
      awscliWrapper.enable = true;
      terraformWrapper.enable = true;

      # Show which profile is being tried (useful for debugging)
      showProfileAttempts = true;

      # Stop after first success (default behavior)
      stopOnFirstSuccess = true;
    };
  };

  # ============================================================================
  # Example 3: Team Workflow (Different Access Levels)
  # ============================================================================

  # Senior engineers have production access, others have staging/dev
  teamWorkflow = {
    stackpanel.aws-vault = {
      enable = true;
      profile = "team-dev";

      # Profiles ordered by permission level (highest to lowest)
      profiles = [
        "team-prod"       # Production (senior engineers only)
        "team-staging"    # Staging (most engineers)
        "team-dev"        # Development (everyone)
        "team-readonly"   # Read-only fallback
      ];

      awscliWrapper.enable = true;
      terraformWrapper.enable = true;
      opentofuWrapper.enable = true;
    };
  };

  # ============================================================================
  # Example 4: Infrastructure Deployment Focus
  # ============================================================================

  # Optimized for deploying infrastructure
  infraDeploy = {
    stackpanel.aws-vault = {
      enable = true;

      profiles = [
        "infra-deploy-prod"
        "infra-deploy-staging"
        "infra-deploy-dev"
      ];

      # Only wrap tools needed for infrastructure
      awscliWrapper.enable = true;
      terraformWrapper.enable = true;

      # Show attempts so we know which account is being used
      showProfileAttempts = true;
    };

    # Enable infrastructure module (works automatically with aws-vault)
    stackpanel.infra.enable = true;
  };

  # ============================================================================
  # Example 5: Multi-Region Setup
  # ============================================================================

  # Different profiles for different regions
  multiRegion = {
    stackpanel.aws-vault = {
      enable = true;

      # Profiles named by region
      profiles = [
        "myapp-us-east-1"
        "myapp-us-west-2"
        "myapp-eu-west-1"
        "myapp-ap-south-1"
      ];

      awscliWrapper.enable = true;
      terraformWrapper.enable = true;
    };
  };

  # ============================================================================
  # Example 6: Silent Mode (No Output)
  # ============================================================================

  # Don't show profile attempts (cleaner output)
  silent = {
    stackpanel.aws-vault = {
      enable = true;

      profiles = [
        "production"
        "staging"
      ];

      awscliWrapper.enable = true;

      # Disable progress messages
      showProfileAttempts = false;
    };
  };

  # ============================================================================
  # Example 7: Try All Profiles (Don't Stop on First Success)
  # ============================================================================

  # Useful for testing which profiles have necessary permissions
  tryAll = {
    stackpanel.aws-vault = {
      enable = true;

      profiles = [
        "prod-admin"
        "staging-admin"
        "dev-admin"
      ];

      awscliWrapper.enable = true;

      # Try all profiles even if one succeeds
      stopOnFirstSuccess = false;
      showProfileAttempts = true;
    };
  };

  # ============================================================================
  # Example 8: Conditional Based on User
  # ============================================================================

  # Different profiles for different team members
  conditional = { lib, ... }:
  let
    # @impure — example only. If a user copies this pattern into their
    # config.nix, evaluation will require --impure. Documented here so it's
    # obvious why.
    user = builtins.getEnv "USER"; # @impure
    isSenior = builtins.elem user ["alice" "bob" "carol"];
    isAdmin = user == "alice";
  in
  {
    stackpanel.aws-vault = {
      enable = true;

      # Dynamically build profile list based on user
      profiles =
        (lib.optional isAdmin "admin")
        ++ (lib.optionals isSenior ["production" "staging"])
        ++ ["development" "readonly"];

      awscliWrapper.enable = true;
      terraformWrapper.enable = true;
    };
  };

  # ============================================================================
  # Example 9: Integration with Other Stackpanel Features
  # ============================================================================

  # Complete setup with secrets, infra, and aws-vault
  fullIntegration = {
    # AWS Vault for credential management
    stackpanel.aws-vault = {
      enable = true;
      profiles = ["prod" "staging" "dev"];
      awscliWrapper.enable = true;
      terraformWrapper.enable = true;
    };

    # Secrets management (uses AWS for backend)
    stackpanel.secrets = {
      enable = true;
      backend = "aws-ssm";
    };

    # Infrastructure deployment (uses aws-vault automatically)
    stackpanel.infra = {
      enable = true;
      modules.aws-ec2.enable = true;
      modules.aws-iam.enable = true;
    };

    # Variables backend using AWS
    stackpanel.variables = {
      backend = "chamber";
      chamber.servicePrefix = "myapp";
    };
  };

  # ============================================================================
  # Example 10: Custom Package Versions
  # ============================================================================

  # Use specific versions of aws-vault or wrapped tools
  customPackages = { pkgs, ... }: {
    stackpanel.aws-vault = {
      enable = true;

      # Use specific aws-vault version
      package = pkgs.aws-vault.overrideAttrs (old: {
        version = "7.2.0";
      });

      profiles = ["production" "staging"];

      # Use specific AWS CLI version
      awscliWrapper = {
        enable = true;
        package = pkgs.awscli2;
      };

      # Use specific Terraform version
      terraformWrapper = {
        enable = true;
        package = pkgs.terraform_1;
      };
    };
  };

  # ============================================================================
  # Example 11: AWS Config File Generation (Programmatic)
  # ============================================================================

  # Define AWS profiles programmatically - generates ~/.aws/config
  configGeneration = {
    stackpanel.aws-vault = {
      enable = true;

      profiles = ["production" "staging" "dev"];

      # Define profiles - automatically generates ~/.aws/config
      awsProfiles = {
        default = {
          region = "us-west-2";
          output = "json";
        };

        production = {
          region = "us-east-1";
          roleArn = "arn:aws:iam::123456789012:role/ProductionRole";
          sourceProfile = "default";
          mfaSerial = "arn:aws:iam::123456789012:mfa/user";
          durationSeconds = 3600;  # 1 hour sessions
        };

        staging = {
          region = "us-east-1";
          roleArn = "arn:aws:iam::123456789012:role/StagingRole";
          sourceProfile = "default";
          durationSeconds = 7200;  # 2 hour sessions
        };

        dev = {
          region = "us-west-2";
          output = "json";
          extraConfig = {
            cli_pager = "";  # Disable pager
            s3_max_concurrent_requests = "20";
          };
        };
      };

      awscliWrapper.enable = true;
      terraformWrapper.enable = true;
    };
  };

  # ============================================================================
  # Example 12: Raw AWS Config File
  # ============================================================================

  # For complete control, specify raw config content
  rawConfig = {
    stackpanel.aws-vault = {
      enable = true;

      profiles = ["production" "staging"];

      # Raw INI-format config
      configFile = ''
        [default]
        region = us-west-2
        output = json

        [profile production]
        region = us-east-1
        role_arn = arn:aws:iam::123456789012:role/ProdRole
        source_profile = default
        mfa_serial = arn:aws:iam::123456789012:mfa/user
        duration_seconds = 3600

        [profile staging]
        region = us-east-1
        role_arn = arn:aws:iam::123456789012:role/StagingRole
        source_profile = default
        duration_seconds = 7200
      '';

      awscliWrapper.enable = true;
    };
  };

  # ============================================================================
  # Example 13: Dynamic Multi-Region Config Generation
  # ============================================================================

  # Generate profiles for multiple regions dynamically
  dynamicRegionConfig = { lib, ... }:
  let
    regions = ["us-east-1" "us-west-2" "eu-west-1" "ap-south-1"];
  in
  {
    stackpanel.aws-vault = {
      enable = true;

      # Profile list for fallback
      profiles = map (region: "myapp-${region}") regions;

      # Generate AWS config for each region
      awsProfiles = lib.listToAttrs (
        map (region: {
          name = "myapp-${region}";
          value = {
            inherit region;
            output = "json";
            roleArn = "arn:aws:iam::123456789012:role/AppRole";
            sourceProfile = "default";
          };
        }) regions
      );

      awscliWrapper.enable = true;
    };
  };

  # ============================================================================
  # Example 14: SSO Profile Configuration
  # ============================================================================

  # Configure AWS SSO profiles
  ssoProfiles = {
    stackpanel.aws-vault = {
      enable = true;

      profiles = ["sso-prod" "sso-staging"];

      awsProfiles = {
        "sso-prod" = {
          region = "us-east-1";
          output = "json";
          extraConfig = {
            sso_start_url = "https://mycompany.awsapps.com/start";
            sso_region = "us-east-1";
            sso_account_id = "123456789012";
            sso_role_name = "ProductionAccess";
          };
        };

        "sso-staging" = {
          region = "us-east-1";
          output = "json";
          extraConfig = {
            sso_start_url = "https://mycompany.awsapps.com/start";
            sso_region = "us-east-1";
            sso_account_id = "123456789012";
            sso_role_name = "StagingAccess";
          };
        };
      };

      awscliWrapper.enable = true;
    };
  };
}

# ==============================================================================
# Usage Examples
# ==============================================================================

# After enabling one of the configurations above:
#
# Setup:
#   1. Enter your devshell: nix develop
#   2. AWS config is automatically generated at ~/.aws/config
#   3. Add your AWS profiles: aws-vault add production
#   4. Verify setup: aws-vault:list-profiles
#   5. Check config: cat ~/.aws/config
#
# Basic usage (single profile):
#   aws s3 ls
#   terraform plan
#
# Multi-profile usage:
#   # Commands automatically try profiles in order
#   aws s3 ls
#   # → Tries production, falls back to staging if needed
#
#   # Use specific profile
#   aws-vault:with-profile staging aws s3 ls
#
#   # Deploy infrastructure
#   infra:deploy --stage prod
#   # → Automatically uses aws-vault with profile fallback
#
# Direct aws-vault commands:
#   aws-vault exec production -- aws s3 ls
#   aws-vault login production
#   aws-vault list
#
# Helper commands (when profiles configured):
#   aws-vault:list-profiles          # Show configured profiles
#   aws-vault:with-profile prod aws s3 ls  # Use specific profile
