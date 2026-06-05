// =============================================================================
// aws-ec2-userdata.ts — User-data script generators for EC2 instances
//
// Two boot strategies:
//
//   amazon-linux (default):
//     Installs Node/Bun via dnf, pulls a tarball artifact from S3,
//     loads runtime env from SSM, writes a systemd unit that runs
//     `node .output/server/index.mjs`.
//
//   nixos:
//     Minimal boot script. The real configuration comes later via
//     Colmena (nixos-rebuild switch) which pulls the pre-built
//     closure from Cachix. UserData is static so the instance is
//     never replaced on deploy — only the NixOS system config changes.
//
// These are pure string-returning functions with no AWS SDK calls.
// =============================================================================

import type { RuntimeLayout } from "./aws-ec2-deploy";

// ---- Amazon Linux 2023 user-data --------------------------------------------

export function buildUserData({
  appName,
  artifactBucket,
  artifactKey,
  artifactVersion,
  layout,
  parameterPath,
  port,
  region,
}: {
  appName: string;
  artifactBucket: string;
  artifactKey: string;
  artifactVersion?: string;
  layout: RuntimeLayout;
  parameterPath: string;
  port: number;
  region: string;
}) {
  return `#!/bin/bash
set -euxo pipefail

export HOME=/root
export PATH=/usr/local/bin:/usr/bin:/bin

dnf update -y
dnf install -y jq unzip nodejs

curl -fsSL https://bun.sh/install | bash
export BUN_INSTALL=/root/.bun
export PATH=$BUN_INSTALL/bin:$PATH

cat >/usr/local/bin/${layout.slug}-bootstrap <<'EOF'
#!/bin/bash
set -euo pipefail

export HOME=/root
export PATH=/root/.bun/bin:/usr/local/bin:/usr/bin:/bin
export AWS_REGION=${shellString(region)}

ARTIFACT_BUCKET=${shellString(artifactBucket)}
ARTIFACT_KEY=${shellString(artifactKey)}
ARTIFACT_VERSION=${shellString(artifactVersion ?? "unknown")}
PARAMETER_PATH=${shellString(trimTrailingSlash(parameterPath))}
APP_ROOT=${shellString(layout.appRoot)}
RELEASE_ROOT=${shellString(layout.releaseRoot)}
ENV_FILE=${shellString(layout.envFile)}
ARCHIVE_PATH=${shellString(layout.archivePath)}

rm -rf "$RELEASE_ROOT"
mkdir -p "$RELEASE_ROOT"

aws s3 cp "s3://$ARTIFACT_BUCKET/$ARTIFACT_KEY" "$ARCHIVE_PATH" --region "$AWS_REGION"
tar -xzf "$ARCHIVE_PATH" -C "$RELEASE_ROOT"

cat >"$ENV_FILE" <<ENVEOF
NODE_ENV=production
HOST=0.0.0.0
PORT=${port}
ARTIFACT_BUCKET=$ARTIFACT_BUCKET
ARTIFACT_KEY=$ARTIFACT_KEY
ARTIFACT_VERSION=$ARTIFACT_VERSION
ENVEOF

aws ssm get-parameters-by-path \\
  --path "$PARAMETER_PATH" \\
  --recursive \\
  --with-decryption \\
  --output json \\
  --region "$AWS_REGION" \\
| jq -r '.Parameters[] | "\\(.Name | split("/")[-1])=\\(.Value)"' >>"$ENV_FILE"
EOF

chmod +x /usr/local/bin/${layout.slug}-bootstrap
/usr/local/bin/${layout.slug}-bootstrap

cat >/etc/systemd/system/${layout.serviceName} <<'EOF'
[Unit]
Description=stackpanel ${appName}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${layout.releaseRoot}
Environment=PATH=/root/.bun/bin:/usr/local/bin:/usr/bin:/bin
EnvironmentFile=${layout.envFile}
ExecStart=/usr/bin/node ${layout.releaseRoot}/.output/server/index.mjs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ${layout.serviceName}
`;
}

// ---- NixOS user-data --------------------------------------------------------

/**
 * NixOS instances get a static boot script that only logs metadata.
 * The actual system configuration is applied later by Colmena, which
 * pulls the pre-built closure from Cachix. Because this script never
 * changes between deploys, the Ec2Instance resource won't trigger
 * a replacement on each deploy.
 */
export function buildNixosUserData({
  region,
  parameterPath,
}: {
  region: string;
  parameterPath: string;
}) {
  return `#!/usr/bin/env bash
set -euo pipefail
exec >> /var/log/user-data.log 2>&1

echo "[+] NixOS instance booted"
echo "[+] SSM parameter path: ${shellString(trimTrailingSlash(parameterPath))}"
echo "[+] Region: ${shellString(region)}"
echo "[+] Instance ready for Colmena deployment"
`;
}

// ---- String helpers ---------------------------------------------------------

function trimTrailingSlash(value: string) {
  return value.endsWith("/") ? value.slice(0, -1) : value;
}

function shellString(value: string) {
  return JSON.stringify(value);
}
