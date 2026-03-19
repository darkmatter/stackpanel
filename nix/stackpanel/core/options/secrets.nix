{
  lib,
  pkgs,
  config,
  self ? null,
  ...
}:
let
  core = import ./secrets-parts/helpers.nix { inherit lib self; };
  optionsPart = import ./secrets-parts/options.nix {
    inherit lib pkgs;
    inherit config;
    inherit (core)
      db
      defaultLocalKey
      masterKeyModule
      recipientModule
      recipientGroupModule
      creationRuleModule
      sopsAgeKeySourceModule
      ;
  };
  configPart = import ./secrets-parts/config.nix {
    inherit lib;
    inherit config;
    inherit (core) derivedRecipientsFromUsers;
  };
in
optionsPart // configPart
