 # ==============================================================================
 # module.nix - AWS EC2 Per-App Options
 #
 # Adds aws-specific options to each app's deployment config via appModules.
 # The actual deployment is handled by the deployment infra module at
 # infra/modules/deployment/.
 # ==============================================================================
 {
   lib,
   ...
 }:
 let
   awsAppModule =
     { ... }:
     {
       options.deployment.aws = {
         region = lib.mkOption {
           type = lib.types.nullOr lib.types.str;
           default = null;
           description = "AWS region override for this app deployment.";
           example = "us-west-2";
         };
 
         availability-zone = lib.mkOption {
           type = lib.types.nullOr lib.types.str;
           default = null;
           description = "Availability zone override for this app deployment.";
           example = "us-west-2a";
         };
 
         image-id = lib.mkOption {
           type = lib.types.nullOr lib.types.str;
           default = null;
           description = "AMI override for this app deployment.";
           example = "ami-0123456789abcdef0";
         };
 
         instance-type = lib.mkOption {
           type = lib.types.nullOr lib.types.str;
           default = null;
           description = "EC2 instance type override for this app deployment.";
           example = "t3.small";
         };
 
         key-name = lib.mkOption {
           type = lib.types.nullOr lib.types.str;
           default = null;
           description = "Optional EC2 key pair name for SSH access.";
           example = "stackpanel-staging";
         };
 
         port = lib.mkOption {
           type = lib.types.nullOr lib.types.port;
           default = null;
           description = "Application port exposed by the EC2 instance.";
           example = 80;
         };
 
         parameter-path = lib.mkOption {
           type = lib.types.nullOr lib.types.str;
           default = null;
           description = "SSM parameter path prefix for runtime environment variables.";
           example = "/stackpanel/staging/web-runtime";
         };
 
         http-cidr-blocks = lib.mkOption {
           type = lib.types.listOf lib.types.str;
           default = [ ];
           description = "IPv4 CIDR blocks allowed to reach the HTTP port.";
           example = [ "0.0.0.0/0" ];
         };
 
         ssh-cidr-blocks = lib.mkOption {
           type = lib.types.listOf lib.types.str;
           default = [ ];
           description = "IPv4 CIDR blocks allowed to reach SSH when key-name is set.";
           example = [ "203.0.113.4/32" ];
         };
 
         root-volume-size = lib.mkOption {
           type = lib.types.nullOr lib.types.int;
           default = null;
           description = "Root EBS volume size in GiB.";
           example = 20;
         };
 
         vpc-cidr-block = lib.mkOption {
           type = lib.types.nullOr lib.types.str;
           default = null;
           description = "CIDR block for the dedicated VPC created for this app.";
           example = "10.42.0.0/16";
         };
 
         subnet-cidr-block = lib.mkOption {
           type = lib.types.nullOr lib.types.str;
           default = null;
           description = "CIDR block for the public subnet created for this app.";
           example = "10.42.1.0/24";
         };
 
         tags = lib.mkOption {
           type = lib.types.attrsOf lib.types.str;
           default = { };
           description = "Additional AWS tags to apply to resources for this app.";
           example = {
             Environment = "staging";
           };
         };

         os-type = lib.mkOption {
           type = lib.types.enum [ "amazon-linux" "nixos" ];
           default = "amazon-linux";
           description = "OS type for the EC2 instance. Use 'nixos' for NixOS AMI + Colmena deploys.";
           example = "nixos";
         };
       };
     };
 in
 {
   options.stackpanel.deployment.aws = {
     region = lib.mkOption {
       type = lib.types.str;
       default = "us-west-2";
       description = "Default AWS region for EC2 deployments.";
       example = "us-west-2";
     };
 
     instance-type = lib.mkOption {
       type = lib.types.str;
       default = "t3.small";
       description = "Default EC2 instance type for app deployments.";
       example = "t3.small";
     };
 
     port = lib.mkOption {
       type = lib.types.port;
       default = 80;
       description = "Default application port exposed by EC2 deployments.";
       example = 80;
     };
 
     artifact = {
       bucket = lib.mkOption {
         type = lib.types.nullOr lib.types.str;
         default = null;
         description = ''
           Optional S3 bucket override for deployment artifacts.
           When null, deploy scripts derive the bucket name dynamically.
         '';
         example = "stackpanel-web-artifacts-123456789012-us-west-2";
       };
 
       key-prefix = lib.mkOption {
         type = lib.types.str;
         default = "web";
         description = "Default S3 key prefix for deployment artifacts.";
         example = "web";
       };
     };
   };
 
   config = {
     stackpanel.appModules = [ awsAppModule ];
   };
 }
