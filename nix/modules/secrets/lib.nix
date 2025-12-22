# Secrets module library functions
# Utility functions for SOPS/vals secrets management
{
  lib,
  pkgs,
  secretsConfigDir,
}: let
  # YAML generation
  yaml = pkgs.formats.yaml {};

  # Parse YAML file to Nix attrset
  # Uses yj (YAML to JSON converter) at build time
  fromYaml = file:
    builtins.fromJSON (
      builtins.readFile (
        pkgs.runCommand "yaml-to-json" {} ''
          ${pkgs.yj}/bin/yj < ${file} > $out
        ''
      )
    );

  # Load YAML file if exists, otherwise return default
  loadYamlIfExists = path: default:
    if builtins.pathExists path
    then fromYaml path
    else default;
in {
  # Convert attrs to YAML string
  toYaml = attrs: builtins.readFile (yaml.generate "sops.yaml" attrs);

  # Re-export fromYaml for use in other modules
  inherit fromYaml loadYamlIfExists;

  # Check if key is an AGE key (matches age1...)
  isAgeKey = key: lib.hasPrefix "age1" key;

  # Get admin users from users attrset
  getAdmins = users: lib.filterAttrs (_: u: u.admin or false) users;

  # Get admin keys from users attrset
  getAdminKeys = users: lib.mapAttrsToList (_: u: u.pubkey) (lib.getAdmins users);

  # Get all user keys
  getAllUserKeys = users: lib.mapAttrsToList (_: u: u.pubkey) users;

  # Load global config (YAML)
  loadGlobalConfig = loadYamlIfExists "${secretsConfigDir}/config.yaml" {};

  # Load users config (YAML)
  loadUsersConfig = loadYamlIfExists "${secretsConfigDir}/users.yaml" {};

  # Auto-discover apps from .stackpanel/secrets/apps/
  # Apps prefixed with _ (like _example) are ignored
  discoverApps = let
    appsDir = "${secretsConfigDir}/apps";
    exists = builtins.pathExists appsDir;
    entries =
      if exists
      then builtins.readDir appsDir
      else {};
    # Filter to directories not starting with _
    validApps = lib.filterAttrs (name: type: type == "directory" && !lib.hasPrefix "_" name) entries;
  in
    lib.mapAttrs (appName: _: let
      appDir = "${appsDir}/${appName}";
      # Load app config (YAML)
      appConfig = loadYamlIfExists "${appDir}/config.yaml" {};
      # Load common schema (YAML)
      commonSchema = loadYamlIfExists "${appDir}/common.yaml" {};
      # Load environment configs (YAML)
      loadEnv = env:
        loadYamlIfExists "${appDir}/${env}.yaml" {
          schema = {};
          users = [];
          extraKeys = [];
        };
    in {
      inherit appConfig commonSchema;
      environments = {
        dev = loadEnv "dev";
        staging = loadEnv "staging";
        prod = loadEnv "prod";
      };
    })
    validApps;

  # Get keys for a specific app/environment
  getAppEnvKeys = {
    apps,
    users,
    appName,
    env,
  }: let
    adminKeys = lib.mapAttrsToList (_: u: u.pubkey) (lib.filterAttrs (_: u: u.admin or false) users);
    appData = apps.${appName} or {};
    envCfg = appData.environments.${env} or {};
    explicitKeys = map (name: users.${name}.pubkey) (envCfg.users or []);
  in
    lib.unique (explicitKeys ++ adminKeys ++ (envCfg.extraKeys or []));

  # Generate .sops.yaml creation rules
  generateSopsRules = {
    apps,
    users,
    isAgeKey,
  }: let
    adminKeys = lib.mapAttrsToList (_: u: u.pubkey) (lib.filterAttrs (_: u: u.admin or false) users);
    allUserKeys = lib.mapAttrsToList (_: u: u.pubkey) users;

    # Get keys for a specific app/environment
    getAppEnvKeys' = appName: env: let
      appData = apps.${appName} or {};
      envCfg = appData.environments.${env} or {};
      explicitKeys = map (name: users.${name}.pubkey) (envCfg.users or []);
    in
      lib.unique (explicitKeys ++ adminKeys ++ (envCfg.extraKeys or []));

    # Build creation rules for each app/environment
    appEnvRules = lib.flatten (lib.mapAttrsToList (appName: appData:
      lib.mapAttrsToList (env: _envCfg: let
        keys = getAppEnvKeys' appName env;
        ageKeys = lib.filter isAgeKey keys;
      in {
        path_regex = "secrets/${appName}/${env}(\\.local)?\\.yaml$";
        age = lib.concatStringsSep "," ageKeys;
      })
      (appData.environments or {}))
    apps);

    # Common secrets per app - all users have access
    appCommonRules = lib.mapAttrsToList (appName: _: {
      path_regex = "secrets/${appName}/common(\\.local)?\\.yaml$";
      age = lib.concatStringsSep "," (lib.filter isAgeKey allUserKeys);
    })
    apps;

    # Filter out rules with empty age keys
    validRules = lib.filter (r: r.age != "") (appCommonRules ++ appEnvRules);
  in {creation_rules = validRules;};
}
