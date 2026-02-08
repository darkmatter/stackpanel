# Test Fixture: Basic
# Minimal configuration with no apps
{
  enable = true;
  name = "test-basic";

  # Disable optional features for minimal test
  cli.enable = false;
  theme.enable = false;
  ide.enable = false;
  motd.enable = false;
}
