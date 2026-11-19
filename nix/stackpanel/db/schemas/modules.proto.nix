# Canonical evaluated module model shared by Nix and the v1 Connect API.
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
  msg = name: fields: proto.mkMessage { inherit name fields; };
in
proto.mkProtoFile {
  name = "stackpanel/agent/v1/module_data.proto";
  package = "stackpanel.agent.v1";
  imports = [ "google/protobuf/struct.proto" ];
  options.go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb/stackpanel/agent/v1;agentv1";
  messages = {
    Module = msg "Module" {
      id = proto.string 1 "";
      enabled = proto.bool 2 "";
      meta = proto.message "ModuleMeta" 3 "";
      source = proto.message "ModuleSource" 4 "";
      features = proto.message "ModuleFeatures" 5 "";
      requires = proto.repeated (proto.string 6 "");
      conflicts = proto.repeated (proto.string 7 "");
      priority = proto.int32 8 "";
      tags = proto.repeated (proto.string 9 "");
      config_schema = proto.optional (proto.string 10 "");
      settings = proto.message "google.protobuf.Struct" 11 "";
      apps = proto.map "string" "ModuleAppConfig" 12 "";
      healthcheck_module = proto.optional (proto.string 13 "");
      flake_inputs = proto.repeated (proto.message "ModuleFlakeInput" 14 "");
      missing_flake_inputs = proto.repeated (proto.message "ModuleFlakeInput" 15 "");
      enable_path = proto.string 16 "";
      config_path = proto.string 17 "";
      actions = proto.map "string" "ModuleAction" 18 "";
      readme_content = proto.optional (proto.string 19 "");
      linked = proto.bool 20 "";
      ui_dev_url = proto.optional (proto.string 21 "");
    };

    ModuleMeta = msg "ModuleMeta" {
      name = proto.string 1 "";
      description = proto.optional (proto.string 2 "");
      icon = proto.optional (proto.string 3 "");
      category = proto.string 4 "";
      author = proto.optional (proto.string 5 "");
      version = proto.optional (proto.string 6 "");
      homepage = proto.optional (proto.string 7 "");
    };

    ModuleSource = msg "ModuleSource" {
      type = proto.string 1 "";
      flake_input = proto.optional (proto.string 2 "");
      path = proto.optional (proto.string 3 "");
      registry_id = proto.optional (proto.string 4 "");
      ref = proto.optional (proto.string 5 "");
    };

    ModuleFeatures = msg "ModuleFeatures" {
      files = proto.bool 1 "";
      scripts = proto.bool 2 "";
      tasks = proto.bool 3 "";
      healthchecks = proto.bool 4 "";
      services = proto.bool 5 "";
      secrets = proto.bool 6 "";
      packages = proto.bool 7 "";
      app_module = proto.bool 8 "";
    };

    ModuleFlakeInput = msg "ModuleFlakeInput" {
      name = proto.string 1 "";
      url = proto.string 2 "";
      follows_nixpkgs = proto.bool 3 "";
      ref = proto.optional (proto.string 4 "");
    };

    ModuleAction = msg "ModuleAction" {
      label = proto.string 1 "";
      description = proto.optional (proto.string 2 "");
      icon = proto.optional (proto.string 3 "");
      args_schema = proto.message "google.protobuf.Struct" 4 "";
      confirm = proto.optional (proto.string 5 "");
      output_mode = proto.string 6 "";
      invalidates = proto.repeated (proto.string 7 "");
    };

    ModuleAppConfig = msg "ModuleAppConfig" {
      enabled = proto.bool 1 "";
      config = proto.message "google.protobuf.Struct" 2 "";
    };

    ModuleOutputs = msg "ModuleOutputs" {
      module_id = proto.string 1 "";
      files = proto.repeated (proto.message "ModuleOutputFile" 2 "");
      scripts = proto.repeated (proto.message "ModuleOutputScript" 3 "");
      packages = proto.repeated (proto.message "ModuleOutputPackage" 4 "");
      tasks = proto.repeated (proto.message "ModuleOutputTask" 5 "");
      services = proto.repeated (proto.message "ModuleOutputService" 6 "");
      healthchecks = proto.repeated (proto.message "ModuleOutputHealthcheck" 7 "");
    };

    ModuleOutputFile = msg "ModuleOutputFile" {
      path = proto.string 1 "";
      description = proto.optional (proto.string 2 "");
      type = proto.string 3 "";
    };

    ModuleOutputScript = msg "ModuleOutputScript" {
      name = proto.string 1 "";
      description = proto.optional (proto.string 2 "");
    };

    ModuleOutputPackage = msg "ModuleOutputPackage" {
      name = proto.string 1 "";
      version = proto.optional (proto.string 2 "");
      description = proto.optional (proto.string 3 "");
    };

    ModuleOutputTask = msg "ModuleOutputTask" {
      name = proto.string 1 "";
      description = proto.optional (proto.string 2 "");
    };

    ModuleOutputService = msg "ModuleOutputService" {
      name = proto.string 1 "";
      description = proto.optional (proto.string 2 "");
      proxy_enabled = proto.bool 3 "";
    };

    ModuleOutputHealthcheck = msg "ModuleOutputHealthcheck" {
      id = proto.string 1 "";
      name = proto.string 2 "";
      description = proto.optional (proto.string 3 "");
      severity = proto.string 4 "";
      type = proto.string 5 "";
    };

    ModulePreview = msg "ModulePreview" {
      files = proto.message "ModulePreviewDiff" 1 "";
      packages = proto.message "ModulePreviewDiff" 2 "";
      services = proto.message "ModulePreviewDiff" 3 "";
      offers = proto.repeated (proto.message "ModuleAdoptionOffer" 4 "");
    };

    ModulePreviewDiff = msg "ModulePreviewDiff" {
      before = proto.repeated (proto.string 1 "");
      after = proto.repeated (proto.string 2 "");
      added = proto.repeated (proto.string 3 "");
      removed = proto.repeated (proto.string 4 "");
      changed = proto.repeated (proto.string 5 "");
    };

    ModuleAdoptionOffer = msg "ModuleAdoptionOffer" {
      id = proto.string 1 "";
      label = proto.string 2 "";
      description = proto.string 3 "";
      revision = proto.string 4 "";
      module = proto.string 5 "";
      reason = proto.string 6 "";
      type = proto.string 7 "Question type: bool, select, or multiselect";
      choices = proto.repeated (proto.message "ModuleAdoptionChoice" 8 "Public choices only");
      default = proto.message "google.protobuf.Value" 9 "Default answer for this question";
    };

    ModuleAdoptionChoice = msg "ModuleAdoptionChoice" {
      label = proto.string 1 "";
      value = proto.string 2 "";
    };

    ModuleAdoptionAnswer = msg "ModuleAdoptionAnswer" {
      id = proto.string 1 "Offer ID";
      revision = proto.string 2 "Revision presented by the preview";
      answer = proto.message "google.protobuf.Value" 3 "Boolean, choice value, or list of choice values";
    };

    RegistryModule = msg "RegistryModule" {
      id = proto.string 1 "";
      slug = proto.string 2 "";
      name = proto.string 3 "";
      description = proto.string 4 "";
      category = proto.string 5 "";
      icon = proto.string 6 "";
      author = proto.string 7 "";
      tier = proto.string 8 "";
      latest_version = proto.string 9 "";
      versions = proto.repeated (proto.message "RegistryModuleVersion" 10 "");
      features = proto.repeated (proto.string 11 "");
      ui_slots = proto.repeated (proto.string 12 "");
      readme_url = proto.string 13 "";
      homepage = proto.string 14 "";
      tags = proto.repeated (proto.string 15 "");
      installed = proto.bool 16 "";
      installed_version = proto.optional (proto.string 17 "");
    };

    RegistryModuleVersion = msg "RegistryModuleVersion" {
      version = proto.string 1 "";
      flake_url = proto.string 2 "";
      ref = proto.string 3 "";
      rev = proto.string 4 "";
      follows_nixpkgs = proto.bool 5 "";
      flake_path = proto.string 6 "";
      flake_inputs = proto.repeated (proto.message "ModuleFlakeInput" 7 "");
    };
  };
}
