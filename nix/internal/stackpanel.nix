# ==============================================================================
# stackpanel.nix
#
# Main devenv configuration for the stackpanel repository itself.
# This file enables core stackpanel features and configures project-specific
# settings for local development of the stackpanel project.
#
# Configures:
#   - Theme and IDE integrations (VSCode)
#   - Recommended devenv settings and formatters
#   - AWS Roles Anywhere authentication
#   - Step CA for internal certificate management
#   - MOTD (Message of the Day) with helpful commands and hints
#
# Imported by the root devenv.nix of the stackpanel repository.
# ==============================================================================

{ pkgs, lib, config, ... }: {
  # Enable core stackpanel features
  stackpanel.theme.enable = true;
  stackpanel.ide.enable = true;
  stackpanel.ide.vscode.enable = true;

  # Devenv recommended settings from stackpanel's module
  stackpanel.devenv.recommended.enable = true;
  stackpanel.devenv.recommended.formatters.enable = true;

  # AWS Roles Anywhere via stackpanel's AWS module
  stackpanel.aws.certAuth = {
    enable = true;
    region = "us-west-2";
    account-id = "950224716579";
    role-name = "darkmatter-dev";
    trust-anchor-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:trust-anchor/c99a9383-6be1-48ba-8e63-c3ab6b7069cb";
    profile-arn = "arn:aws:rolesanywhere:us-west-2:950224716579:profile/4e72b392-9074-4e53-8cd0-1ba50856d1ca";
  };

  # Step CA
  stackpanel.network.step = {
    enable = true;
    ca-url = "https://ca.internal:443";
    ca-fingerprint = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
  };



  # MOTD content
  stackpanel.motd.commands = [
    { name = "stackpanel status"; description = "Show all service status"; }
    { name = "stackpanel services start"; description = "Start dev services"; }
    { name = "stackpanel caddy add"; description = "Add a Caddy site"; }
    { name = "stackpanel certs ensure"; description = "Get device certificate"; }
    { name = "bun install"; description = "Install dependencies"; }
    { name = "bun run dev"; description = "Start development server"; }
  ];
  stackpanel.motd.hints = [
    "Run 'stackpanel --help' for all commands"
    "Run 'devenv up' to start all processes"
  ];
}
