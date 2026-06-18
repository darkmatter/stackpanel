# ==============================================================================
# config.nix
#
# Stackpanel project configuration (starter).
#
# Generated from the current option schema.
#
# To see the latest options and examples (after upgrading stackpanel):
#   stack config generate --output .stack/config.nix.example
#
# Review the generated .example and copy/merge sections you need.
# ==============================================================================
{
  cli = {
    enable = false;
    quiet = false;
  };

  deploy = {
    apiUrl = "https://api.stackpanel.com";
    stateBackend = "local";
  };

  devshell = {
    buildInputs = [ ];
    clean = {
      aliases = [ ];
      enable = false;
      impure = true;
      keep = [
        "HOME"
        "USER"
        "LOGNAME"
        "SHELL"
        "TMPDIR"
        "TERM"
        "COLORTERM"
        "TERM_PROGRAM"
        "TERM_PROGRAM_VERSION"
        "LANG"
        "LC_ALL"
        "LC_CTYPE"
        "SSH_AUTH_SOCK"
        "SSH_SOCKET_DIR"
        "GPG_AGENT_INFO"
        "GNUPGHOME"
        "EDITOR"
        "VISUAL"
        "PAGER"
        "__CF_USER_TEXT_ENCODING"
        "COMMAND_MODE"
      ];
      keepDirenv = [
        "DIRENV_DIR"
        "DIRENV_FILE"
      ];
      keepFzf = [
        "FZF_DEFAULT_COMMAND"
        "FZF_DEFAULT_OPTS"
        "FZF_CTRL_T_COMMAND"
        "FZF_ALT_C_COMMAND"
      ];
      keepGui = [
        "DISPLAY"
        "WAYLAND_DISPLAY"
        "XDG_RUNTIME_DIR"
        "DBUS_SESSION_BUS_ADDRESS"
      ];
      keepWarp = [
        "WARP_HONOR_PS1"
        "WARP_IS_LOCAL_SHELL_SESSION"
        "WARP_USE_SSH_WRAPPER"
      ];
      keepXdg = [
        "XDG_CACHE_HOME"
        "XDG_CONFIG_HOME"
        "XDG_DATA_HOME"
        "XDG_STATE_HOME"
      ];
    };
    env = { };
    hooks = {
      after = [ ];
      before = [ ];
      main = [ ];
    };
    nativeBuildInputs = [ ];
    packages = [ ];
    path = {
      append = [ ];
      prepend = [ ];
    };
    timing = false;
  };

  direnv = {
    hide-env-diff = true;
  };

  dirs = {
    home = ".stack";
  };

  enable = true;

  envs = { };

  flakeApps = { };

  git-hooks = { };

  gitignore = {
    defaults = {
      addProjectMarker = false;
      localConfig = true;
      projectMarker = false;
      stackpanelState = true;
      tasksDir = true;
    };
    enable = true;
    entries = [ ];
  };

  moduleRequirements = { };

  modules = { };

  name = "my-project";

  panels = { };

  project = {
    name = "my-project";
    type = "github";
  };

  root-marker = ".stackpanel-root";

  secrets = {
    backend = "sops";
    chamber = {
      service-prefix = "my-project";
    };
    codegen = { };
    creation-rules = [ ];
    enable = false;
    environments = { };
    groups = { };
    input-directory = null;
    kms = {
      aws-profile = null;
      aws-role-arn = null;
      key-arn = null;
    };
    master-keys = {
      local = {
        age-pub = "";
        ref = "ref+file://.stack/keys/local.txt";
      };
    };
    recipient-groups = { };
    recipients = { };
    secrets-dir = null;
    sops-age-keys = {
      op-refs = [ ];
      paths = [ ];
      repo-key-path = ".stack/keys/local.txt";
      sources = [
        {
          name = "User key path";
          type = "user-key-path";
          value = "$HOME/Library/Application Support/sops/age/keys.txt";
        }
        {
          name = "Repo key path";
          type = "repo-key-path";
          value = ".stack/keys/local.txt";
        }
      ];
      user-key-path = "$HOME/Library/Application Support/sops/age/keys.txt";
    };
    system-keys = [ ];
  };

  serializable = { };

  state = {
    custom = { };
    devenv = { };
    file = "stackpanel.json";
  };

  userPackages = {
    enable = true;
  };

  variables = { };
}
