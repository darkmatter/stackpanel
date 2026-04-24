# ==============================================================================
# motd.nix
#
# MOTD - Message of the day shown on shell entry.
# ==============================================================================
{
  enable = true;
  commands = [
    {
      name = "dev";
      description = "Start development server";
    }
    {
      name = "build";
      description = "Build the project";
    }
  ];
}
