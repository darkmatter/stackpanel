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
      sopsAgeSourceLines
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
      sshEd25519RecipientKeys
      secretFilesMeta
      manifestJson
      sopsConfigText
      secretsLib
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
