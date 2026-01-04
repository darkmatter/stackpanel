# ==============================================================================
# step-ca.nix
#
# Step CA certificate management options.
#
# This module imports options from the proto schema (db/schemas/step-ca.proto.nix)
# and extends them with any Nix-specific runtime options.
#
# The proto schema is the SINGLE SOURCE OF TRUTH for the data structure.
# ==============================================================================
{ lib, ... }:
let
  # Import the db module to get proto-derived options
  db = import ../../db { inherit lib; };
in
{
  # Step CA options derived from proto schema
  # The proto defines: enable, ca_url, ca_fingerprint, provisioner, cert_name, prompt_on_shell
  # These are converted to kebab-case: ca-url, ca-fingerprint, cert-name, prompt-on-shell
  options.stackpanel.step-ca = db.extend.stepCa;
}
