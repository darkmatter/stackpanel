# Test Fixture: External Module
# Basic config for testing external module integration
{
  enable = true;
  name = "test-external-module";

  cli.enable = false;
  theme.enable = false;
  ide.enable = false;
  motd.enable = false;

  devshell.profile.enable = false;
  prelude.enable = false;
  registries = [ "https://registry.example.test/modules.json" ];
  modules.fixture-preview.enable = false;
}
