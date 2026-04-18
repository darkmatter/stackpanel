# Auto-import module.nix
{ ... }: {
  imports = [ ./options.nix ./module.nix ];
}
