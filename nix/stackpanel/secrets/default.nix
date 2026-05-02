{
  pkgs,
  lib,
  config,
  ...
}:
let
  ctx = import ./default-parts/context.nix {
    inherit pkgs lib config;
  };

  scripts = import ./default-parts/scripts.nix {
    inherit pkgs lib;
    inherit (ctx)
      cfg
      cfgLib
      projectRoot
      secretsLib
      masterKeysConfig
      sopsAgeSources
      sopsAgeSourceLines
      sopsAgeKeyPaths
      sopsAgeKeyOpRefs
      sopsKeyservices
      recipientsConfig
      ;
  };

  cfgPart = import ./default-parts/config.nix {
    inherit lib config pkgs;
    inherit (ctx)
      cfg
      isChamber
      chamberCfg
      variablesBackend
      recipientNames
      recipientsConfig
      normalizedRecipientPubkeys
      secretFilesMeta
      manifestJson
      cfgLib
      sopsConfigText
      secretsLib
      sopsAgeKeyPaths
      sopsAgeKeyOpRefs
      sopsKeyservices
      ;
    inherit (scripts)
      sopsAgeKeys
      sopsWrapped
      rekeyScriptText
      secretsSet
      secretsGet
      secretsList
      secretsRekey
      secretsLoad
      sopsAgeKeychainSave
      sopsAgeRecipientsInit
      ;
    inherit (ctx) legacySecretsCleanupScript;
  };
in
{
  imports = [
  ];

  inherit (cfgPart) config;
}
