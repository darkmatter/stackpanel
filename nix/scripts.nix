{pkgs, ...}: {
  packages = [
    pkgs.starship
    pkgs.nil
    pkgs.nixd
    pkgs.bashInteractive
    pkgs.neovim
  ];

  scripts.alchemy-needs-setup = {
    description = "Check if Alchemy CLI needs setup";
    exec = ''
      echo "TODO"
    '';
  };
  scripts.alchemy-setup = {
    description = "Setup Alchemy CLI";
    exec = ''
      ${pkgs.bun}/bin/bun create alchemy-project my-alchemy-app
    '';
  };
}
