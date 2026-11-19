{
  description = "Example Stackpanel module";

  outputs = _: {
    stackpanelModules.default = import ./module.nix;
  };
}
