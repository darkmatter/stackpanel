{
  isValidKey = key: builtins.match "^[a-z0-9][a-z0-9-]*$" key != null;
  is25519 = key: builtins.match "^ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA[A-Za-z0-9+/]+=*$" key != null;
}