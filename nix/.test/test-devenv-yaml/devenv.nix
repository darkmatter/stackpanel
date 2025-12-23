# Minimal test config for devenv.yaml path
{pkgs, ...}: {
  stackpanel.enable = true;
  
  # Just a basic sanity check
  packages = [pkgs.hello];
  
  enterShell = ''
    echo "✅ devenv.yaml import works!"
  '';
}

