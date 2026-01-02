# ==============================================================================
# users.nix
#
# User configuration for stackpanel.users option.
# Imports from github-collaborators.nix and transforms to required format.
#
# Edit this file to:
#   - Add non-GitHub users (e.g., CI bots)
#   - Customize secrets-allowed-environments per user
#   - Override display names
#
# The github-collaborators.nix is auto-generated and should not be edited.
# ==============================================================================
let
  ghCollabs = import ./github-collaborators.nix;

  # Transform a GitHub collaborator to stackpanel user format
  toUser = name: collab: {
    inherit name;
    github = collab.login;
    public-keys = collab.publicKeys;
    # Default environments based on admin status
    secrets-allowed-environments = 
      if collab.isAdmin 
      then [ "dev" "staging" "production" ]
      else [ "dev" ];
  };

  # Convert all collaborators
  githubUsers = builtins.mapAttrs toUser ghCollabs.collaborators;

  # Additional non-GitHub users (e.g., CI bots)
  additionalUsers = {
    # Example CI user:
    # ci = {
    #   name = "CI Bot";
    #   public-keys = [ "age1..." ];
    #   secrets-allowed-environments = [ "dev" "staging" "production" ];
    # };
  };

  # Override specific user settings here
  userOverrides = {
    # Example: give a specific user more access
    # someuser = {
    #   secrets-allowed-environments = [ "dev" "staging" ];
    # };
  };

  # Merge function that applies overrides
  applyOverrides = users: 
    builtins.mapAttrs (name: user: 
      user // (userOverrides.${name} or {})
    ) users;

in
  applyOverrides (githubUsers // additionalUsers)
