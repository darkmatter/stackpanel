# Step CA certificate utilities - pure functions that work with any Nix module system
#
# Usage:
#   let networkLib = import ./lib/network.nix { inherit pkgs lib; };
#   in networkLib.mkStepScripts { ... }
#
{
  pkgs,
  lib,
}: {
  # Create Step CA certificate management scripts
  # Returns an attrset of derivations that can be added to packages
  mkStepScripts = {
    # Directory where certs/keys are stored
    stateDir,
    # Step CA URL (e.g., "https://ca.internal:443")
    caUrl,
    # Step CA fingerprint
    caFingerprint,
    # Step CA provisioner name
    provisioner ? "Authentik",
    # Common name for the device certificate
    certName ? "device",
    # Certificate duration (default: 24h)
    duration ? "24h",
  }: let
    certPath = "${stateDir}/device-root.chain.crt";
    keyPath = "${stateDir}/device.key";

    caHost = lib.removePrefix "https://" (lib.removeSuffix ":443" caUrl);

    checkCert = pkgs.writeShellScriptBin "check-device-cert" ''
      set -uo pipefail

      red='\033[0;31m'
      green='\033[0;32m'
      nc='\033[0m'

      pass() { echo -e "''${green}OK''${nc}"; }
      fail() { echo -e "''${red}FAIL''${nc}"; }

      all_passed=true

      echo -n "Checking if CA is reachable... "
      if ${pkgs.netcat}/bin/nc -z -w 3 "${caHost}" 443 2>/dev/null; then
        pass
      else
        fail
        echo "  Hint: Is Tailscale connected?"
        all_passed=false
      fi

      echo -n "Checking if root cert is installed... "
      if [[ -f "$HOME/.step/certs/root_ca.crt" ]]; then
        pass
      else
        fail
        echo "  Hint: Run 'ensure-device-cert' to bootstrap"
        all_passed=false
      fi

      echo -n "Checking if fingerprint matches... "
      if actual_fp=$(${pkgs.step-cli}/bin/step ca roots --ca-url="${caUrl}" 2>/dev/null | \
         ${pkgs.step-cli}/bin/step certificate fingerprint 2>/dev/null); then
        if [[ "$actual_fp" == "${caFingerprint}" ]]; then
          pass
        else
          fail
          echo "  Expected: ${caFingerprint}"
          echo "  Got:      $actual_fp"
          all_passed=false
        fi
      else
        fail
        echo "  Hint: Could not reach CA to verify fingerprint"
        all_passed=false
      fi

      echo -n "Checking if device certificate exists... "
      if [[ -f "${certPath}" && -f "${keyPath}" ]]; then
        pass
      else
        fail
        echo "  Hint: Run 'ensure-device-cert' to generate"
        all_passed=false
      fi

      if [[ -f "${certPath}" ]]; then
        echo -n "Checking if device certificate is valid... "
        if ${pkgs.step-cli}/bin/step certificate verify "${certPath}" --roots="$HOME/.step/certs/root_ca.crt" 2>/dev/null; then
          pass
        else
          fail
          echo "  Hint: Certificate may be expired or invalid"
          all_passed=false
        fi
      fi

      echo ""
      if $all_passed; then
        echo -e "''${green}All checks passed!''${nc}"
        exit 0
      else
        echo -e "''${red}Some checks failed.''${nc}"
        exit 1
      fi
    '';

    ensureCert = pkgs.writeShellScriptBin "ensure-device-cert" ''
      set -euo pipefail

      if [[ -f "${certPath}" && -f "${keyPath}" ]]; then
        echo "Device certificate already exists at ${certPath}"
        exit 0
      fi

      echo "Setting up device certificate..."
      mkdir -p "${stateDir}"

      if [[ ! -f "$HOME/.step/certs/root_ca.crt" ]]; then
        echo "Bootstrapping CA trust..."
        ${pkgs.step-cli}/bin/step ca bootstrap \
          --ca-url "${caUrl}" \
          --fingerprint "${caFingerprint}" \
          --install
      else
        echo "CA already bootstrapped, skipping..."
      fi

      echo "Verifying CA fingerprint..."
      actual_fingerprint=$(${pkgs.step-cli}/bin/step ca roots --ca-url="${caUrl}" | \
        ${pkgs.step-cli}/bin/step certificate fingerprint)
      if [[ "$actual_fingerprint" != "${caFingerprint}" ]]; then
        echo "ERROR: CA fingerprint mismatch!"
        echo "  Expected: ${caFingerprint}"
        echo "  Got:      $actual_fingerprint"
        exit 1
      fi
      echo "CA fingerprint verified."

      echo "Requesting device certificate..."
      device_cert="${stateDir}/device.crt"
      ${pkgs.step-cli}/bin/step ca certificate \
        "${certName}" \
        "$device_cert" \
        "${keyPath}" \
        --provisioner="${provisioner}" \
        --ca-url="${caUrl}"

      echo "Fetching root CA certificate..."
      root_cert="${stateDir}/root_ca.crt"
      ${pkgs.step-cli}/bin/step ca roots \
        "$root_cert" \
        --ca-url="${caUrl}"

      echo "Assembling certificate chain..."
      cat "$device_cert" "$root_cert" > "${certPath}"

      chmod 600 "${keyPath}"
      chmod 644 "${certPath}"

      echo "Device certificate chain created at ${certPath}"
    '';

    renewCert = pkgs.writeShellScriptBin "renew-device-cert" ''
      set -euo pipefail

      if [[ ! -f "${certPath}" || ! -f "${keyPath}" ]]; then
        echo "No existing certificate found. Run 'ensure-device-cert' first."
        exit 1
      fi

      echo "Renewing device certificate..."
      ${pkgs.step-cli}/bin/step ca renew \
        "${certPath}" \
        "${keyPath}" \
        --force
      echo "Certificate renewed successfully!"
    '';
  in {
    inherit checkCert ensureCert renewCert;
    # Required packages
    requiredPackages = [pkgs.step-cli];
    # All packages together
    allPackages = [checkCert ensureCert renewCert pkgs.step-cli];
    # Paths for use by other modules
    paths = {
      cert = certPath;
      key = keyPath;
    };
  };
}
