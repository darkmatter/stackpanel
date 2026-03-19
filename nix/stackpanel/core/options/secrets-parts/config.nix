{
  lib,
  config,
  derivedRecipientsFromUsers,
}:
{
  config = lib.mkIf config.stackpanel.secrets.enable {
    stackpanel.secrets.all-public-keys =
      let
        recipients =
          derivedRecipientsFromUsers config.stackpanel.users // config.stackpanel.secrets.recipients;
      in
      lib.mkDefault (lib.unique (lib.mapAttrsToList (_: recipient: recipient.public-key) recipients));
  };
}
