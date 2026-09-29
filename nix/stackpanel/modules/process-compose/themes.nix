{ lib, preludeThemes }:
let
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
lib.mapAttrs mkProcessComposeTheme preludeThemes
