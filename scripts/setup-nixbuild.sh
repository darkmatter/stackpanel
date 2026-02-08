#!/usr/bin/env bash
# =============================================================================
# nixbuild.net Remote Builder Setup for macOS
# =============================================================================
#
# This script sets up nixbuild.net as a remote builder for Nix on macOS.
# It's required for cross-platform builds (e.g., building x86_64-linux
# containers from aarch64-darwin).
#
# Prerequisites:
#   - A nixbuild.net account (https://nixbuild.net)
#   - sudo access
#
# Usage:
#   ./scripts/setup-nixbuild.sh
#
# After running this script:
#   1. Copy the displayed public key
#   2. Add it at https://app.nixbuild.net/settings/ssh-keys
#   3. Test with: nix build nixpkgs#hello --system x86_64-linux
#
# =============================================================================

set -euo pipefail

KEY_PATH="/etc/nix/nixbuild_ed25519"
MACHINES_FILE="/etc/nix/machines"
KNOWN_HOSTS="/etc/ssh/ssh_known_hosts"

# nixbuild.net host key (from their documentation)
NIXBUILD_HOST_KEY="eu.nixbuild.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM"

echo "🔧 Setting up nixbuild.net remote builder..."
echo

# Step 1: Create /etc/nix if it doesn't exist
if [[ ! -d /etc/nix ]]; then
    echo "📁 Creating /etc/nix directory..."
    sudo mkdir -p /etc/nix
fi

# Step 2: Generate SSH key if it doesn't exist
if [[ -f "$KEY_PATH" ]]; then
    echo "🔑 SSH key already exists at $KEY_PATH"
else
    echo "🔑 Generating Ed25519 SSH key for nixbuild.net..."
    sudo ssh-keygen -t ed25519 -C "nixbuild-$(hostname)" -f "$KEY_PATH" -N ""
    sudo chmod 600 "$KEY_PATH"
    sudo chmod 644 "${KEY_PATH}.pub"
fi

# Step 3: Add nixbuild.net host key to known_hosts
if grep -q "eu.nixbuild.net" "$KNOWN_HOSTS" 2>/dev/null; then
    echo "🌐 nixbuild.net already in known_hosts"
else
    echo "🌐 Adding nixbuild.net host key to known_hosts..."
    echo "$NIXBUILD_HOST_KEY" | sudo tee -a "$KNOWN_HOSTS" > /dev/null
fi

# Step 4: Configure the machines file for Nix
echo "⚙️  Configuring Nix remote builders..."
sudo tee "$MACHINES_FILE" > /dev/null << EOF
eu.nixbuild.net x86_64-linux $KEY_PATH 100 1 big-parallel,benchmark
EOF

# Step 5: Restart the Nix daemon
echo "🔄 Restarting Nix daemon..."
if launchctl list | grep -q "determinate"; then
    # Determinate Nix
    sudo launchctl kickstart -k system/systems.determinate.nix-daemon 2>/dev/null || true
elif launchctl list | grep -q "org.nixos.nix-daemon"; then
    # Standard Nix
    sudo launchctl kickstart -k system/org.nixos.nix-daemon 2>/dev/null || true
else
    echo "⚠️  Could not detect Nix daemon service. You may need to restart it manually."
fi

echo
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "✅ Setup complete!"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo
echo "📋 NEXT STEPS:"
echo
echo "1. Copy this public key:"
echo "   ────────────────────────────────────────────────────────────────────────────"
sudo cat "${KEY_PATH}.pub"
echo "   ────────────────────────────────────────────────────────────────────────────"
echo
echo "2. Add it to your nixbuild.net account:"
echo "   https://app.nixbuild.net/settings/ssh-keys"
echo
echo "3. Test the connection:"
echo "   sudo ssh -i $KEY_PATH eu.nixbuild.net shell"
echo
echo "4. Test a remote build:"
echo "   nix build nixpkgs#hello --system x86_64-linux"
echo
echo "5. Build containers:"
echo "   turbo run container:build"
echo
