# ==============================================================================
# team.nix (Template)
#
# Team member configuration for stackpanel secrets management.
# This file defines team members with their public keys for age encryption.
# Generated and managed by the stackpanel agent.
#
# Safe to commit - contains only public keys, never private keys.
#
# Structure:
#   users.<name> = {
#     github = "github-username";     # GitHub username for key sync
#     pubkey = "ssh-ed25519 AAAA..."; # SSH public key (or age public key)
#     admin = true/false;             # Whether user has admin privileges
#   };
# ==============================================================================
{
  users = {
    # Add team members here or sync from GitHub via stackpanel agent
    # example = {
    #   github = "example";
    #   pubkey = "ssh-ed25519 AAAA...";
    #   admin = false;
    # };
  };
}
