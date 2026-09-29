{ lib }:
let
  # Ported from darkmatter/prelude src/prelude/themes.nix at the pinned
  # Stackpanel Prelude revision. Keep token names aligned with Prelude so
  # stackpanel.prelude.theme can select the matching Process Compose style.
  palettes = {
    phosphor = {
      bg = "#0c110e";
      surface = "#131715";
      secondary = "#202622";
      fg = "#d5e2d7";
      muted = "#7d8a81";
      dim = "#5d665f";
      border = "#1a201d";
      accent = "#68e371";
      accent2 = "#f9b64f";
      success = "#68e371";
      warning = "#f9b64f";
      info = "#5eb7ff";
      error = "#e6443d";
      selectionFg = "#0c110e";
    };

    minted = {
      bg = "#0c0c13";
      surface = "#161623";
      secondary = "#24243f";
      fg = "#979db5";
      muted = "#6a6c85";
      dim = "#4a5085";
      border = "#1d1d2f";
      accent = "#f2cdcd";
      accent2 = "#CC99FF";
      success = "#b7ce99";
      warning = "#f2c17d";
      info = "#89b4fa";
      error = "#ee848e";
      selectionFg = "#0c0c13";
    };

    amber = {
      bg = "#110c08";
      surface = "#19120e";
      secondary = "#291f18";
      fg = "#fcbe62";
      muted = "#a97c46";
      dim = "#8d6a43";
      border = "#261c14";
      accent = "#ffc761";
      accent2 = "#fadc7d";
      success = "#a8c66c";
      warning = "#fadc7d";
      info = "#7fb4ca";
      error = "#e9523f";
      selectionFg = "#110c08";
    };

    solarized = {
      bg = "#0d2323";
      surface = "#162e2d";
      secondary = "#203838";
      fg = "#8b9c9d";
      muted = "#6d7e7f";
      dim = "#566768";
      border = "#1c3232";
      accent = "#75a33e";
      accent2 = "#ba9232";
      success = "#859900";
      warning = "#b58900";
      info = "#268bd2";
      error = "#db4241";
      selectionFg = "#031a1a";
    };

    nord = {
      bg = "#2e333d";
      surface = "#383d48";
      secondary = "#424853";
      fg = "#d3d8e0";
      muted = "#979fab";
      dim = "#79818d";
      border = "#3e434e";
      accent = "#96ce9d";
      accent2 = "#e2cc91";
      success = "#a3be8c";
      warning = "#ebcb8b";
      info = "#88c0d0";
      error = "#d55753";
      selectionFg = "#292e38";
    };

    gruvbox = {
      bg = "#282622";
      surface = "#33302b";
      secondary = "#3e3a34";
      fg = "#e2d7ba";
      muted = "#968f7b";
      dim = "#817a66";
      border = "#3a3632";
      accent = "#b2cb52";
      accent2 = "#eebc4a";
      success = "#b8bb26";
      warning = "#fabd2f";
      info = "#83a598";
      error = "#e9483d";
      selectionFg = "#282622";
    };

    mono = {
      bg = "#0a0a0a";
      surface = "#121212";
      secondary = "#1c1c1c";
      fg = "#e5e5e5";
      muted = "#8a8a8a";
      dim = "#5c5c5c";
      border = "#1c1c1c";
      accent = "#ebebeb";
      accent2 = "#a3a3a3";
      success = "#ebebeb";
      warning = "#c7c7c7";
      info = "#a3a3a3";
      error = "#ffffff";
      selectionFg = "#0a0a0a";
    };

    apathy = {
      bg = "#0e0b13";
      surface = "#1b1629";
      secondary = "#2a2441";
      fg = "#aabbbb";
      muted = "#7d7a8b";
      dim = "#4d4a56";
      border = "#2a2630";
      accent = "#77f5c9";
      accent2 = "#ffcb6b";
      success = "#77f5c9";
      warning = "#ffcb6b";
      info = "#82aaff";
      error = "#e61f44";
      selectionFg = "#0e0b13";
    };

    paper = {
      bg = "#f4f2ec";
      surface = "#faf8f4";
      secondary = "#e6e4df";
      fg = "#252a27";
      muted = "#545a55";
      dim = "#6e736e";
      border = "#e2e0da";
      accent = "#1e7729";
      accent2 = "#9f6200";
      success = "#1e7729";
      warning = "#9f6200";
      info = "#2563a6";
      error = "#cc2827";
      selectionFg = "#f7f5f1";
    };

    prelude = {
      bg = "#0e0b13";
      surface = "#1b1621";
      secondary = "#8787af";
      fg = "#c0c0c0";
      muted = "#8787af";
      dim = "#444444";
      border = "#444444";
      accent = "#ff87d7";
      accent2 = "#c1f98e";
      success = "#c1f98e";
      warning = "#ffd787";
      info = "#87d7ff";
      error = "#ff005f";
      selectionFg = "#0e0b13";
    };
  };

  mkProcessComposeTheme =
    name: palette:
    {
      style = {
        name = "Prelude ${name}";
        body = {
          fgColor = palette.fg;
          bgColor = palette.bg;
          secondaryTextColor = palette.accent2;
          tertiaryTextColor = palette.success;
          borderColor = palette.border;
        };
        stat_table = {
          keyFgColor = palette.accent2;
          valueFgColor = palette.fg;
          logoColor = palette.accent;
        };
        proc_table = {
          fgColor = palette.info;
          fgWarning = palette.warning;
          fgPending = palette.dim;
          fgCompleted = palette.success;
          fgError = palette.error;
          headerFgColor = palette.accent2;
        };
        help = {
          fgColor = palette.fg;
          keyColor = palette.accent;
          hlColor = palette.secondary;
          categoryFgColor = palette.accent2;
        };
        dialog = {
          fgColor = palette.fg;
          bgColor = palette.surface;
          contrastBgColor = palette.secondary;
          attentionBgColor = palette.error;
          buttonFgColor = palette.selectionFg;
          buttonBgColor = palette.accent;
          buttonFocusFgColor = palette.selectionFg;
          buttonFocusBgColor = palette.info;
          labelFgColor = palette.accent2;
          fieldFgColor = palette.fg;
          fieldBgColor = palette.secondary;
        };
      };
    };
in
lib.mapAttrs mkProcessComposeTheme palettes
