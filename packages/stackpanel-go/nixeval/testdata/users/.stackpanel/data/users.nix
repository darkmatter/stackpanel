{
  alice = {
    name = "Alice Example";
    github = "alicehub";
    "public-keys" = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey" ];
    "secrets-allowed-environments" = [
      "dev"
      "production"
    ];
  };
}
