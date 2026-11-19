# JSON views of evaluated Stackpanel state. Never walk an arbitrary derivation
# looking for displayable values: even inspecting its outPath can instantiate
# a whole build graph. Project executable paths only for public capabilities.
{ lib }:
let
  select = names: builtins.intersectAttrs (lib.genAttrs names (_: null));
  canAccess = value: (builtins.tryEval value).success;
  safeAccess =
    value:
    let
      result = builtins.tryEval value;
    in
    if result.success then result.value else null;
  isSerializable =
    value:
    if builtins.isList value then
      builtins.all isSerializable value
    else if builtins.isAttrs value then
      !(lib.isDerivation value || value ? _type || value ? __functor)
    else
      builtins.elem (builtins.typeOf value) [
        "null"
        "bool"
        "int"
        "float"
        "string"
        "path"
      ];

  # Generic (non-evaluated) Nix data: omit opaque/internal values. Check keys
  # before values, including in lists of records, so skipped thunks stay lazy.
  filterSerializableWithSkip =
    skip: value:
    let
      visible = v: canAccess v && (builtins.isList v || isSerializable v);
      walk =
        v:
        if builtins.isAttrs v then
          lib.mapAttrs (_: walk) (
            lib.filterAttrs (k: item: !(lib.hasPrefix "_" k) && !(builtins.elem k skip) && visible item) v
          )
        else if builtins.isList v then
          map walk (builtins.filter visible v)
        else if builtins.isPath v then
          toString v
        else
          v;
    in
    if visible value then walk value else null;

  defaultSkipAttrs = [
    "outputs"
    "appBuildPackages"
    "appBuildProviders"
    "containerBuilders"
    "modulePackages"
    "packagesResolved"
    "appModules"
    "commandModules"
    "taskModules"
    "serviceModules"
    "nixosModules"
    "users"
    "userPackages"
    "env"
    "envs"
  ];
  filterSerializableAttrs = filterSerializableWithSkip defaultSkipAttrs;

  serializePackage = pkg: {
    name = if builtins.isString pkg then pkg else pkg.pname or pkg.name or "unknown";
    version = if builtins.isString pkg then "" else pkg.version or "";
    attrPath =
      if builtins.isString pkg then pkg else pkg.meta.mainProgram or pkg.pname or pkg.name or "";
    source = "devshell";
  };
  outputDescriptors = import ./module-outputs.nix { inherit lib serializePackage; };

  # Minimal cross-project inventory for the local proxy. Count primary ports
  # even for unattributed services which do not grant proxy access themselves.
  proxyPortInventory = services: {
    schemaVersion = 1;
    ports = lib.sort builtins.lessThan (
      lib.unique (
        lib.concatMap (
          service:
          if service.enable then
            lib.filter (port: port != null) (
              [ service.port ] ++ lib.optional service.proxy.enable service.proxy.port
            )
          else
            [ ]
        ) (lib.attrValues services)
      )
    );
  };

  # This is a public wire contract, not a dump of config.stackpanel. In
  # particular, env values (including those embedded in hooks, generated files,
  # process-compose configs and service commands) never cross this boundary.
  projectState =
    input:
    let
      # Additional namespaces may be private/expensive. Even a built-in can
      # replace its public view with an explicit `serializable.<id>` projection.
      cfg = builtins.removeAttrs input (input.lazyNamespaces or [ ]);
      descriptors = outputDescriptors cfg;
      extra = lib.mapAttrs (
        id: value:
        assert assertSerializable "stackpanel.serializable.${id}" value;
        value
      ) (cfg.serializable or { });
      modulesListAll = cfg.modulesListAll or [ ];
      panelsList = cfg.panelsList or [ ];
      providerFields = [
        "module"
        "label"
        "icon"
        "description"
      ];
      appRuntimes = lib.mapAttrs (_: select providerFields) (cfg.appRuntimes or { });
      appFrameworks = lib.mapAttrs (
        _:
        select (
          providerFields
          ++ [
            "defaultTasks"
            "compatibleRuntimes"
          ]
        )
      ) (cfg.appFrameworks or { });
      enabled = options: key: { enable = options.${key}.enable or false; };
      apps = lib.mapAttrs (
        name: app:
        select [ "name" "path" "description" "enable" ] app
        // select [ "port" "url" "domain" "tls" "offset" ] (cfg.appsComputed.${name} or { })
        // lib.genAttrs (builtins.attrNames appRuntimes) (enabled app)
        // {
          framework = lib.genAttrs (builtins.attrNames appFrameworks) (enabled (app.framework or { }));
        }
      ) (cfg.apps or { });
      checks = map (select [
        "id"
        "module"
        "name"
        "description"
        "enabled"
        "type"
        "severity"
        "tags"
        "timeout"
        "scriptPath"
        "scriptDrvPath"
        "scriptSource"
        "nixExpr"
        "httpUrl"
        "httpMethod"
        "httpExpectedStatus"
        "tcpHost"
        "tcpPort"
        "interval"
      ]) (cfg.healthchecksList or [ ]);
      doctorList = map (select [
        "id"
        "module"
        "displayName"
        "name"
        "description"
        "enabled"
        "scope"
        "type"
        "severity"
        "tags"
        "fixCommand"
        "timeout"
        "checkName"
        "required"
        "nixExpr"
        "scriptPath"
        "httpUrl"
        "httpMethod"
        "httpExpectedStatus"
        "tcpHost"
        "tcpPort"
      ]) (cfg.doctorList or [ ]);
    in
    extra
    // select [
      "name"
      "enable"
      "debug"
      "github"
      "root-marker"
      "dirs"
      "ports"
      "theme"
      "addonsList"
      "moduleRequirements"
      "moduleChecksCertification"
    ] cfg
    // descriptors
    // {
      inherit
        modulesListAll
        apps
        panelsList
        appRuntimes
        appFrameworks
        doctorList
        ;
      moduleOutputs = cfg.moduleOutputs or descriptors.moduleOutputs;
      serializable = extra;
      # Project URL strings and executable registrations, not provider functions.
      registries = cfg.registries or [ ];
      deployBackends = lib.mapAttrs (_: select (providerFields ++ [ "script" ])) (
        cfg.deployBackends or { }
      );
      deploymentHosts = lib.mapAttrs (_: select providerFields) (cfg.deploymentHosts or { });
      autoImportInputs = cfg.autoImportInputs or true;
      healthchecksList = checks;
      variables =
        (extra.variables or { })
        // lib.mapAttrs (
          _:
          select [
            "id"
            "keyGroup"
            "varName"
            "isSecret"
            "isComputed"
          ]
        ) (cfg.variables or { });
      devshell._commandsSerializable = lib.mapAttrs (
        _:
        select [
          "module"
          "name"
          "description"
          "args"
          "binPath"
          "source"
          "timeout"
        ]
      ) (cfg.devshell._commandsSerializable or { });
    };

  # Authenticated project configuration, used by config editors, `stack
  # commands`, and variable resolution. This deliberately retains configured
  # app options, environments and variable values. Never send it to frames or
  # use it in place of the allowlisted module state above.
  projectConfig =
    input:
    let
      state = projectState input;
      cfg = builtins.removeAttrs input (input.lazyNamespaces or [ ]);
      # These are evaluated independently, either by Nix build/run or by the
      # metadata-only projection. Remove by key, *before* touching the value.
      skipRoots = [
        "users"
        "userPackages"
        "appModules"
        "commandModules"
        "taskModules"
        "serviceModules"
        "outputs"
        "checks"
        "nixosModules"
        "flakeApps"
        "appsComputed"
        "commandsComputed"
        "tasksComputed"
        "containersComputed"
        "packagesResolved"
        "moduleChecksFlattened"
        "appBuildProviders"
        "appBuildPackages"
        "containerBuilders"
        "modulePackages"
        "util"
        "doctorList"
        "healthchecksList"
        "healthchecksComputed"
        "moduleOutputs"
        "devshell"
        "modules"
        "modulesComputedAll"
        "modulesListAll"
        "panels"
        "panelsComputed"
        "panelsList"
        "serializable"
      ];
      # Ignore build inputs without skipping unrelated user namespaces (e.g.
      # an app named `go`). The private registry/tree is never recursively
      # walked to decide which packages are present.
      raw = filterSerializableWithSkip [
        "derivation"
        "drv"
        "runtimeInputs"
        "scriptPackage"
        "wrappedTooling"
      ] (builtins.removeAttrs cfg skipRoots);
    in
    state.serializable
    // raw
    // {
      inherit (state)
        modulesListAll
        moduleOutputs
        panelsList
        serializable
        appRuntimes
        appFrameworks
        deploymentHosts
        deployBackends
        healthchecksList
        doctorList
        ;
      projectName = cfg.ports.project-name or cfg.name or "default";
      # The raw variable registry includes values. Keep backend metadata used
      # by Chamber alongside it, without replacing the registry with that metadata.
      variables = (state.serializable.variables or { }) // (raw.variables or { });
      devshell = state.devshell // {
        env = cfg.devshell.env or { };
      };
    };

  filterSerializable =
    value:
    if builtins.isAttrs value then
      filterSerializableAttrs (builtins.removeAttrs value (value.lazyNamespaces or [ ]))
    else
      filterSerializableAttrs value;

  assertSerializable =
    name: value:
    let
      check =
        path: v:
        if !(isSerializable v) then
          throw "Value at ${path} cannot be serialized to JSON"
        else if builtins.isAttrs v then
          builtins.deepSeq (lib.mapAttrs (k: check "${path}.${k}") v) true
        else if builtins.isList v then
          builtins.deepSeq (lib.imap0 (i: check "${path}[${toString i}]") v) true
        else
          true;
    in
    check name value;
  trySerialize = value: safeAccess (builtins.toJSON value);
in
{
  inherit
    isSerializable
    filterSerializable
    filterSerializableWithSkip
    filterSerializableAttrs
    assertSerializable
    trySerialize
    safeAccess
    canAccess
    defaultSkipAttrs
    serializePackage
    outputDescriptors
    projectState
    projectConfig
    proxyPortInventory
    ;
}
