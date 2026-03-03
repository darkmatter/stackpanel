# Test Fixture: External Module
# Basic config for testing external module integration
{
  enable = true;
  name = "test-external-module";

  cli.enable = false;
  theme.enable = false;
  ide.enable = false;
  motd.enable = false;

  # External modules would add their config here
  # Example:
  # modules.my-external-module.enable = true;
}
