# ==============================================================================
# infra/modules/aws-ec2-app/module.nix
#
# EC2 app provisioning module (app-centric).
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.infra.aws-ec2-app;

  sshType = lib.types.submodule {
    options = {
      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "SSH user for the instance.";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 22;
        description = "SSH port for the instance.";
      };

      key-path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SSH private key path for the instance.";
      };
    };
  };

  ruleType = lib.types.submodule {
    options = {
      from-port = lib.mkOption {
        type = lib.types.int;
        description = "Start port for the rule.";
      };

      to-port = lib.mkOption {
        type = lib.types.int;
        description = "End port for the rule.";
      };

      protocol = lib.mkOption {
        type = lib.types.str;
        default = "tcp";
        description = "Protocol for the rule (tcp, udp, -1).";
      };

      cidr-blocks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "IPv4 CIDR blocks for the rule.";
      };

      ipv6-cidr-blocks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "IPv6 CIDR blocks for the rule.";
      };

      security-group-ids = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Source/target security group IDs for the rule.";
      };

      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional rule description.";
      };
    };
  };

  securityGroupType = lib.types.submodule {
    options = {
      create = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Create a security group for this app.";
      };

      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Security group name (defaults to app name).";
      };

      description = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Security group description.";
      };

      ingress = lib.mkOption {
        type = lib.types.listOf ruleType;
        default = [ ];
        description = "Ingress rules.";
      };

      egress = lib.mkOption {
        type = lib.types.listOf ruleType;
        default = [ ];
        description = "Egress rules.";
      };

      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Tags applied to the security group.";
      };
    };
  };

  keyPairType = lib.types.submodule {
    options = {
      create = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Import the key pair from a public key.";
      };

      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Key pair name.";
      };

      public-key = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Public key material for the key pair.";
      };

      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Tags applied to the key pair.";
      };

      destroy-on-delete = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Delete the key pair during destroy.";
      };
    };
  };

  inlinePolicyType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Inline policy name.";
      };

      document = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        description = "IAM policy document (JSON object).";
      };
    };
  };

  iamType = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Create an IAM role and instance profile for the app.";
      };

      role-name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "IAM role name (defaults to app name).";
      };

      assume-role-policy = lib.mkOption {
        type = lib.types.nullOr (lib.types.attrsOf lib.types.anything);
        default = null;
        description = "Optional assume role policy document (defaults to EC2 trust).";
      };

      managed-policy-arns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
          "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        ];
        description = "Managed policy ARNs to attach.";
      };

      inline-policies = lib.mkOption {
        type = lib.types.listOf inlinePolicyType;
        default = [ ];
        description = "Inline policies to attach to the role.";
      };

      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Tags applied to the IAM role.";
      };

      instance-profile-name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Instance profile name (defaults to role name + '-profile').";
      };

      instance-profile-tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Tags applied to the instance profile.";
      };
    };
  };

  nixosType = lib.types.submodule {
    options = {
      ami-id = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Explicit NixOS AMI ID (optional).";
      };

      flake-url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "FlakeHub URL (e.g., darkmatter/infra).";
      };

      host-config = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "NixOS host config name.";
      };

      flake-version = lib.mkOption {
        type = lib.types.str;
        default = "*";
        description = "FlakeHub version constraint (e.g., '*', '0.1').";
      };
    };
  };

  albHealthCheckType = lib.types.submodule {
    options = {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable target group health checks.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "/";
        description = "Health check path.";
      };

      protocol = lib.mkOption {
        type = lib.types.enum [ "HTTP" "HTTPS" "TCP" ];
        default = "HTTP";
        description = "Health check protocol.";
      };

      port = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Health check port (null for traffic port).";
      };

      interval = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Health check interval in seconds.";
      };

      timeout = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "Health check timeout in seconds.";
      };

      healthy-threshold = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Healthy threshold count.";
      };

      unhealthy-threshold = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Unhealthy threshold count.";
      };

      matcher = lib.mkOption {
        type = lib.types.str;
        default = "200-399";
        description = "HTTP matcher for health checks.";
      };
    };
  };

  albTargetGroupType = lib.types.submodule {
    options = {
      port = lib.mkOption {
        type = lib.types.int;
        default = 80;
        description = "Target group port.";
      };

      protocol = lib.mkOption {
        type = lib.types.enum [ "HTTP" "HTTPS" "TCP" ];
        default = "HTTP";
        description = "Target group protocol.";
      };

      health-check = lib.mkOption {
        type = albHealthCheckType;
        default = { };
        description = "Target group health check configuration.";
      };
    };
  };

  albType = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable an application load balancer for the app.";
      };

      create = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create a new ALB (false uses existing listener ARNs).";
      };

      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "ALB name override.";
      };

      scheme = lib.mkOption {
        type = lib.types.enum [ "internet-facing" "internal" ];
        default = "internet-facing";
        description = "ALB scheme.";
      };

      ip-address-type = lib.mkOption {
        type = lib.types.enum [ "ipv4" "dualstack" ];
        default = "ipv4";
        description = "ALB IP address type.";
      };

      subnet-ids = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Subnets for the ALB.";
      };

      security-group-ids = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Security group IDs for the ALB.";
      };

      http = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create an HTTP listener on port 80.";
      };

      https = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Create an HTTPS listener on port 443.";
      };

      certificate-arn = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "ACM certificate ARN for HTTPS listener.";
      };

      ssl-policy = lib.mkOption {
        type = lib.types.str;
        default = "ELBSecurityPolicy-TLS13-1-2-2021-06";
        description = "SSL policy for HTTPS listener.";
      };

      existing-listener-http-arn = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Existing shared HTTP listener ARN.";
      };

      existing-listener-https-arn = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Existing shared HTTPS listener ARN.";
      };

      hostnames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Hostnames to route to the app target group.";
      };

      host-rule-priority = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Priority for the host-based listener rule.";
      };

      target-group = lib.mkOption {
        type = albTargetGroupType;
        default = { };
        description = "Target group configuration.";
      };
    };
  };

  githubOidcType = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable GitHub OIDC role for ECR push.";
      };

      repo-owner = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "GitHub repository owner.";
      };

      repo-name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "GitHub repository name.";
      };

      allowed-branches = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Branches allowed to assume the role.";
      };

      allowed-workflows = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Workflow file paths allowed to assume the role.";
      };

      allow-tags = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow tag refs to assume the role.";
      };

      role-name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "IAM role name for GitHub Actions.";
      };

      oidc-provider-arn = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Existing GitHub OIDC provider ARN.";
      };

      create-oidc-provider = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Create a GitHub OIDC provider if none is provided.";
      };
    };
  };

  ecrType = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable ECR repository provisioning.";
      };

      create = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create the ECR repository if it does not exist.";
      };

      repo-name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "ECR repository name override.";
      };

      image-tag-mutability = lib.mkOption {
        type = lib.types.enum [ "MUTABLE" "IMMUTABLE" ];
        default = "MUTABLE";
        description = "ECR image tag mutability.";
      };

      scan-on-push = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable ECR scan on push.";
      };

      lifecycle-policy = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional lifecycle policy JSON string.";
      };

      github = lib.mkOption {
        type = githubOidcType;
        default = { };
        description = "GitHub Actions OIDC role for ECR push.";
      };
    };
  };

  ssmType = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable SSM parameter wiring for app environment.";
      };

      region = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "AWS region for SSM parameters.";
      };

      path-prefix = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SSM path prefix (defaults to /<app>).";
      };

      parameters = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Plaintext SSM parameters.";
      };

      secure-parameters = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "SecureString SSM parameters.";
      };

      env-file-path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Env file path on the instance.";
      };

      refresh-script-path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Refresh script path on the instance.";
      };

      install-cli = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install awscli/jq when rendering the refresh script (ubuntu only).";
      };

      use-chamber = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use chamber instead of awscli for env refresh.";
      };
    };
  };

  machineMetaType = lib.types.submodule {
    options = {
      tags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Machine tags for Colmena targeting.";
      };

      roles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Machine roles for Colmena targeting.";
      };

      target-env = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Deployment environment label for the machine.";
      };

      arch = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Target system architecture (e.g., x86_64-linux).";
      };

      ssh = lib.mkOption {
        type = sshType;
        default = { };
        description = "SSH settings for the instance.";
      };
    };
  };

  instanceType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Instance name override.";
      };

      ami = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "AMI override.";
      };

      os-type = lib.mkOption {
        type = lib.types.enum [ "ubuntu" "nixos" ];
        default = "ubuntu";
        description = "Operating system type for AMI lookup.";
      };

      nixos = lib.mkOption {
        type = nixosType;
        default = { };
        description = "NixOS deployment settings.";
      };

      instance-type = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "EC2 instance type.";
      };

      subnet-id = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Subnet ID for this instance.";
      };

      security-group-ids = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Security group IDs for this instance.";
      };

      key-name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "EC2 key pair name.";
      };

      iam-instance-profile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "IAM instance profile name.";
      };

      user-data = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "User data script override.";
      };

      root-volume-size = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Root volume size in GB.";
      };

      associate-public-ip = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Associate a public IP address.";
      };

      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Tags applied to the EC2 instance.";
      };

      machine = lib.mkOption {
        type = machineMetaType;
        default = { };
        description = "Machine metadata for Colmena.";
      };
    };
  };

  appType = lib.types.submodule {
    options = {
      instance-count = lib.mkOption {
        type = lib.types.int;
        default = 1;
        description = "Number of instances to create (ignored if instances list is set).";
      };

      instances = lib.mkOption {
        type = lib.types.listOf instanceType;
        default = [ ];
        description = "Per-instance overrides.";
      };

      ami = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "AMI override for all instances.";
      };

      os-type = lib.mkOption {
        type = lib.types.enum [ "ubuntu" "nixos" ];
        default = "ubuntu";
        description = "Operating system type for AMI lookup.";
      };

      nixos = lib.mkOption {
        type = nixosType;
        default = { };
        description = "NixOS deployment settings.";
      };

      instance-type = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "EC2 instance type override.";
      };

      vpc-id = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "VPC ID override.";
      };

      subnet-ids = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Subnet IDs for the app.";
      };

      security-group-ids = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Security group IDs for the app.";
      };

      security-group = lib.mkOption {
        type = securityGroupType;
        default = { };
        description = "Optional security group configuration.";
      };

      key-name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "EC2 key pair name.";
      };

      key-pair = lib.mkOption {
        type = keyPairType;
        default = { };
        description = "Optional key pair configuration.";
      };

      iam = lib.mkOption {
        type = iamType;
        default = { };
        description = "Optional IAM role/profile configuration.";
      };

      iam-instance-profile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "IAM instance profile name override.";
      };

      user-data = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "User data script for instances.";
      };

      root-volume-size = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Root volume size in GB.";
      };

      associate-public-ip = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Associate a public IP address.";
      };

      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Tags applied to the EC2 instances.";
      };

      alb = lib.mkOption {
        type = albType;
        default = { };
        description = "Application Load Balancer configuration.";
      };

      ecr = lib.mkOption {
        type = ecrType;
        default = { };
        description = "ECR repository and GitHub OIDC configuration.";
      };

      ssm = lib.mkOption {
        type = ssmType;
        default = { };
        description = "SSM parameter wiring for app environment.";
      };

      machine = lib.mkOption {
        type = machineMetaType;
        default = { };
        description = "Machine metadata defaults for Colmena.";
      };
    };
  };
in
{
  options.stackpanel.infra.aws-ec2-app = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable EC2 app provisioning.";
    };

    defaults = lib.mkOption {
      type = appType;
      default = { };
      description = "Default settings applied to all apps.";
    };

    apps = lib.mkOption {
      type = lib.types.attrsOf appType;
      default = { };
      description = "App definitions keyed by app name.";
    };

    sync-outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "instanceIds" "publicIps" "publicDns" "privateIps" "machines" "albOutputs" "ecrOutputs" "ssmOutputs" ];
      description = "Which outputs to sync to the storage backend.";
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.infra.enable = lib.mkDefault true;

    stackpanel.infra.modules.aws-ec2-app = {
      name = "AWS EC2 Apps";
      description = "Provision EC2 instances for apps and emit machine inventory";
      path = ./index.ts;
      inputs = {
        defaults = cfg.defaults;
        apps = cfg.apps;
      };
      dependencies = {
        "@aws-sdk/client-ec2" = "catalog:";
        "@aws-sdk/client-iam" = "catalog:";
        "@aws-sdk/client-elastic-load-balancing-v2" = "catalog:";
        "@aws-sdk/client-ecr" = "catalog:";
        "@aws-sdk/client-ssm" = "catalog:";
        "@aws-sdk/client-sts" = "catalog:";
      };
      outputs =
        let
          mkOutput = key: desc: {
            description = desc;
            sensitive = false;
            sync = builtins.elem key cfg.sync-outputs;
          };
        in
        {
          instanceIds = mkOutput "instanceIds" "Instance IDs (JSON)";
          publicIps = mkOutput "publicIps" "Instance public IPs (JSON)";
          publicDns = mkOutput "publicDns" "Instance public DNS (JSON)";
          privateIps = mkOutput "privateIps" "Instance private IPs (JSON)";
          machines = mkOutput "machines" "Machine inventory (JSON)";
          albOutputs = mkOutput "albOutputs" "ALB outputs per app (JSON)";
          ecrOutputs = mkOutput "ecrOutputs" "ECR outputs per app (JSON)";
          ssmOutputs = mkOutput "ssmOutputs" "SSM outputs per app (JSON)";
        };
    };
  };
}
