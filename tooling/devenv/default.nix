{...}: {
  imports = [
    ./services.nix
    ./apps.agent.nix
    ./apps.cli.nix
    ./apps.docs.nix
    ./apps.web.nix
  ];
}