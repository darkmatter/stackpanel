# Legacy module entry point
#
# Historically, consumers referenced `stackpanel/nix/modules/devenv.nix`.
# The clearer path is now the directory import:
# - devenv.yaml: `imports: - stackpanel/nix/modules/devenv`
#
# This file remains as a small compatibility shim.
import ./devenv/devenv.nix


