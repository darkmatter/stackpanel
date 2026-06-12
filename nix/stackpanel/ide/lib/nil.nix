{ pkgs, ... }: {
  config.stackpanel.ide.zed.settings.lsp.nil.binary.path = "${pkgs.nil}/bin/nil";
}
