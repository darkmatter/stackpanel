# devshell sops module
#
# Hardened sops package that reduces instances of keys not being found
# when running in devenv shells.
{ pkgs, ... }: {
  config = {
    # SOPS commands using stackpanel abstraction
    stackpanel.devshell.commands = {
      ensure-age-key-dev = {
        exec = ''
          KEYFILE="''${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

          while read -r line; do
            [[ "$line" == AGE-SECRET-KEY-* ]] || continue
            derived="$(printf '%s\n' "$line" | ${pkgs.age}/bin/age-keygen -y - | awk '{print $NF}')"
            if [[ "$derived" == "$AGE_PUBLIC_KEY_DEV" ]]; then
              [[ "$1" != "-q" ]] && echo "✅ Dev age key found in $KEYFILE"
              exit 0
            fi
          done < "$KEYFILE"

          echo "❌ Error: Dev age key not found in $_f"
          echo "Follow the instructions to add the decryption key:" >&2
          echo "1. Find 'SOPS (Dev)' in 1Password > Dev Vault" >&2
          echo "2. Copy the AGE secret key (password)" >&2
          echo "3. Add it to $KEYFILE (create the file if it doesn't exist)" >&2
          echo "4. Try again" >&2
          exit 1
        '';
      };

      sops = {
        exec = ''
          # Run preflight check before sops
          ensure-age-key-dev -q || exit 1
          export SOPS_AGE_KEY_FILE="''${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
          ${pkgs.sops}/bin/sops "$@"
        '';
      };
    };
  };
}