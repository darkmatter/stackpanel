# Stackpanel Infrastructure Module System — Implementation Plan

## Overview

Build a generic infrastructure module system for stackpanel that replaces SST. The system provides:

- **A module registry** where developers contribute infra modules (AWS, Fly, Cloudflare, etc.)
- **A generated library** (`@stackpanel/infra`) with an `Infra` class that handles input resolution (including AGE decryption), resource ID scoping, and output collection
- **Pluggable output storage** (SOPS, Chamber, SSM) for persisting deployment outputs
- **An outputs stub** enabling cross-resource references via `.stackpanel/data/infra-outputs.nix`

The framework does **not** dictate what resources a module creates. Module developers write normal alchemy TypeScript. The framework provides the plumbing: inputs in, outputs out.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      Nix Configuration                        │
│                                                              │
│  stackpanel.infra.enable = true;                             │
│  stackpanel.infra.storage-backend.type = "chamber";          │
│  stackpanel.infra.aws.secrets.enable = true;                 │
│                                                              │
│  Each infra module:                                          │
│    1. Defines options (stackpanel.infra.<provider>.*)         │
│    2. Registers in stackpanel.infra.modules with:            │
│       - path: ./index.ts (real TypeScript file)              │
│       - inputs: { region, kms, iam, ... } (from options)     │
│       - outputs: { role-arn: { sync: true }, ... }           │
│       - dependencies: { "@aws-sdk/client-kms": "..." }      │
└──────────────────────┬───────────────────────────────────────┘
                       │
            codegen.nix generates:
                       │
                       ▼
┌──────────────────────────────────────────────────────────────┐
│              Generated: packages/infra/                       │
│                                                              │
│  src/index.ts          Infra class (inputs, id, outputs)     │
│  src/types.ts          Per-module input TypeScript interfaces │
│  src/resources/*.ts    Custom alchemy resources (KMS)         │
│  modules/*.ts          Copied from module path attributes     │
│  alchemy.run.ts        Orchestrator (import → collect → sync) │
│  package.json          Union of all module dependencies       │
│  tsconfig.json         TypeScript config                      │
└──────────────────────────────────────────────────────────────┘

State files (gitignored):
  .stackpanel/state/infra-inputs.json   ← serialized module inputs
  .stackpanel/data/infra-outputs.nix    ← outputs from last deploy
```

## Developer Experience

### Module developer writes a normal TypeScript file:

```typescript
// nix/stackpanel/infra/modules/aws-secrets/index.ts
import { Role } from "alchemy/aws";
import Infra from "@stackpanel/infra";
import { KmsKey } from "@stackpanel/infra/resources/kms-key";
import { KmsAlias } from "@stackpanel/infra/resources/kms-alias";

const infra = new Infra("aws-secrets");
const inputs = infra.inputs(process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES);

const role = await Role(infra.id("role"), {
  roleName: inputs.iam.roleName,
  assumeRolePolicy: {
    Version: "2012-10-17",
    Statement: [{
      Effect: "Allow",
      Principal: { Federated: inputs.oidc.providerArn },
      Action: "sts:AssumeRoleWithWebIdentity",
      Condition: { /* from inputs.oidc */ },
    }],
  },
});

const key = await KmsKey(infra.id("kms-key"), {
  description: `KMS key for ${inputs.kms.alias}`,
  enableKeyRotation: true,
  deletionWindowInDays: inputs.kms.deletionWindowDays,
});

const alias = await KmsAlias(infra.id("kms-alias"), {
  aliasName: `alias/${inputs.kms.alias}`,
  targetKeyId: key.keyId,
});

export default {
  roleArn: role.arn,
  roleName: role.roleName,
  kmsKeyArn: key.arn,
  kmsKeyId: key.keyId,
  kmsAliasName: alias.aliasName,
};
```

### Module developer writes a Nix module alongside:

```nix
# nix/stackpanel/infra/modules/aws-secrets/module.nix
{ lib, config, ... }:
let
  cfg = config.stackpanel.infra.aws.secrets;
  projectName = config.stackpanel.name or "my-project";
in {
  options.stackpanel.infra.aws.secrets = {
    enable = lib.mkOption { type = lib.types.bool; default = false; };
    region = lib.mkOption { type = lib.types.str; default = "us-west-2"; };
    account-id = lib.mkOption { type = lib.types.str; default = ""; };
    kms = { /* alias, deletion-window-days, enable */ };
    iam = { /* role-name, additional-policies */ };
    oidc = { /* provider, github-actions, flyio, roles-anywhere */ };
    sync-outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "roleArn" "kmsKeyArn" "kmsAliasName" ];
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.infra.modules.aws-secrets = {
      name = "AWS Secrets Infrastructure";
      path = ./index.ts;
      inputs = {
        region = cfg.region;
        accountId = cfg.account-id;
        kms = {
          inherit (cfg.kms) enable alias;
          deletionWindowDays = cfg.kms.deletion-window-days;
        };
        iam = { roleName = cfg.iam.role-name; };
        oidc = { /* serialized from cfg.oidc */ };
      };
      dependencies = {
        "@aws-sdk/client-kms" = "catalog:";
        "@aws-sdk/client-iam" = "catalog:";
      };
      outputs = {
        roleArn = { sync = true; description = "IAM role ARN"; };
        kmsKeyArn = { sync = true; description = "KMS key ARN"; };
        kmsKeyId = { sync = true; };
        kmsAliasName = { sync = true; };
      };
    };
  };
}
```

## The `Infra` Class

### API

```typescript
export default class Infra {
  constructor(moduleId: string);

  /**
   * Resolve inputs for this module.
   *
   * Resolution order (highest priority first):
   *   1. overrides parameter (JSON string or object)
   *   2. STACKPANEL_INFRA_INPUTS env var (path to JSON file)
   *   3. .stackpanel/state/infra-inputs.json
   *
   * If any value matches the AGE-encrypted pattern (ENC[age,...]),
   * it is decrypted using the STACKPANEL_AGE_KEY env var.
   */
  inputs<T = Record<string, any>>(overrides?: string | Record<string, any>): T;

  /**
   * Scoped alchemy resource identifier.
   * Prevents collisions between modules.
   *
   * infra.id("role") → "aws-secrets-role"
   * infra.id("kms-key") → "aws-secrets-kms-key"
   */
  id(resourceName: string): string;

  /**
   * Static: sync all module outputs to the configured storage backend.
   * Called by the generated alchemy.run.ts after all modules run.
   *
   * modules: { "aws-secrets": { outputs: {...}, syncKeys: ["roleArn", ...] } }
   */
  static syncAll(modules: Record<string, {
    outputs: Record<string, string>;
    syncKeys: string[];
  }>): Promise<void>;
}
```

### Input resolution with AGE decryption

The inputs JSON written to `.stackpanel/state/infra-inputs.json` can include AGE-encrypted
values for sensitive config:

```json
{
  "__config__": {
    "storageBackend": { "type": "chamber", "service": "stackpanel-infra" },
    "keyFormat": "$module-$key",
    "projectName": "stackpanel"
  },
  "aws-secrets": {
    "region": "us-west-2",
    "accountId": "ENC[age,YWdlLWVuY3J5cHRpb24...]",
    "kms": { "alias": "stackpanel-secrets", "deletionWindowDays": 30 }
  }
}
```

The `inputs()` method walks the parsed object and decrypts any `ENC[age,...]` values using
the AGE key from `STACKPANEL_AGE_KEY` env var (already available in the devshell from
`.stackpanel/state/keys/`).

### Output sync backends

`Infra.syncAll()` reads the `__config__.storageBackend` from the inputs JSON and dispatches:

| Backend   | Behavior |
|-----------|----------|
| `chamber` | `execSync('chamber write <service> <formatted-key> -- <value>')` per synced output |
| `sops`    | Accumulate all outputs -> write YAML -> `sops --encrypt` -> write to configured path |
| `ssm`     | `SSMParameter` alchemy resource per synced output at `<prefix>/<formatted-key>` |
| `none`    | No-op (outputs are still returned, just not persisted) |

Key formatting uses the `keyFormat` template: `"$module-$key"` -> `"aws-secrets-roleArn"`.

## Nix Options Schema

### Core (`options.stackpanel.infra.*`)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | `bool` | `false` | Enable infrastructure module system |
| `framework` | `enum ["alchemy"]` | `"alchemy"` | IaC framework |
| `output-dir` | `str` | `"packages/infra"` | Directory for generated files |
| `key-format` | `str` | `"$module-$key"` | Template for output storage keys |
| `storage-backend.type` | `enum` | `"none"` | `"chamber"`, `"sops"`, `"ssm"`, `"none"` |
| `storage-backend.chamber.service` | `str` | `""` | Chamber service name |
| `storage-backend.sops.file-path` | `str` | `".stack/secrets/vars/infra.sops.yaml"` | SOPS output file |
| `storage-backend.ssm.prefix` | `str` | `""` | SSM path prefix |
| `modules` | `attrsOf submodule` | `{}` | Internal module registry (see below) |
| `package.name` | `str` | `"@${projectName}/infra"` | Package name |
| `package.dependencies` | `attrsOf str` | `{}` | Extra dependencies |
| `outputs` | `attrsOf (attrsOf str)` | `{}` | Outputs from last deploy (read from data file) |

### Module registry entry (`stackpanel.infra.modules.<id>`)

| Option | Type | Description |
|--------|------|-------------|
| `name` | `str` | Human-readable module name |
| `description` | `str` | Description |
| `path` | `path` | Path to TypeScript module file |
| `inputs` | `attrsOf anything` | Config values passed at runtime via JSON |
| `dependencies` | `attrsOf str` | NPM dependencies |
| `outputs` | `attrsOf submodule` | Output declarations (description, sensitive, sync) |

### AWS Secrets module (`options.stackpanel.infra.aws.secrets`)

Mirrors the existing `stackpanel.sst` options for easy migration:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | `bool` | `false` | Enable AWS secrets infrastructure |
| `region` | `str` | `"us-west-2"` | AWS region |
| `account-id` | `str` | `""` | AWS account ID |
| `kms.enable` | `bool` | `true` | Create KMS key |
| `kms.alias` | `str` | `"${projectName}-secrets"` | KMS key alias |
| `kms.deletion-window-days` | `int` | `30` | KMS deletion window |
| `iam.role-name` | `str` | `"${projectName}-secrets-role"` | IAM role name |
| `oidc.provider` | `enum` | `"github-actions"` | OIDC provider type |
| `oidc.github-actions.*` | | | GitHub org, repo, branch |
| `oidc.flyio.*` | | | Fly.io org-id, app-name |
| `oidc.roles-anywhere.*` | | | Trust anchor ARN |
| `sync-outputs` | `listOf str` | `["roleArn" ...]` | Which outputs to sync |

## Outputs Stub

Cross-resource references work via a data file:

```nix
# In options.nix — the stub
options.stackpanel.infra.outputs = lib.mkOption {
  type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
  default = {};
  description = ''
    Infrastructure outputs from the last deployment.
    Keyed by module ID, then by output key.
    Populated by `infra:pull-outputs`. Example:
      config.stackpanel.infra.outputs.aws-secrets.roleArn
  '';
};

# In config — auto-load from data file
config.stackpanel.infra.outputs = let
  outputsFile = config.stackpanel.root + "/.stackpanel/data/infra-outputs.nix";
in lib.optionalAttrs (builtins.pathExists outputsFile) (import outputsFile);
```

Lifecycle:
1. `infra:deploy` -> alchemy provisions resources, syncs outputs to storage backend
2. `infra:pull-outputs` -> reads from storage backend, writes `.stackpanel/data/infra-outputs.nix`
3. Next `nix develop` -> outputs available at `config.stackpanel.infra.outputs.*`

Other modules can then reference them:
```nix
cloudflare.workers.website.env.AWS_ROLE_ARN = config.stackpanel.infra.outputs.aws-secrets.roleArn;
```

## File Structure

### New files

```
nix/stackpanel/infra/
├── default.nix                          # Module aggregator
├── options.nix                          # Core options schema + outputs stub
├── codegen.nix                          # Code generation engine
└── modules/
    └── aws-secrets/
        ├── module.nix                   # Nix options + registration
        └── index.ts                     # Alchemy TypeScript implementation
```

### Modified files

| File | Change |
|------|--------|
| `nix/stackpanel/default.nix` | Add `./infra` to imports list |

### Generated files (via `stackpanel.files.entries`)

All output to `packages/infra/`:

| File | Type | Description |
|------|------|-------------|
| `src/index.ts` | Generated | `Infra` class with embedded project config |
| `src/types.ts` | Generated | Per-module input TypeScript interfaces |
| `src/resources/kms-key.ts` | Static | Custom alchemy `Resource` for AWS KMS Key |
| `src/resources/kms-alias.ts` | Static | Custom alchemy `Resource` for AWS KMS Alias |
| `modules/<id>.ts` | Copied | Module TypeScript files (from `path` attrs) |
| `alchemy.run.ts` | Generated | Orchestrator: import -> collect -> sync |
| `package.json` | Generated | Union of all module dependencies + alchemy |
| `tsconfig.json` | Static | TypeScript configuration |

### State files (gitignored)

| File | Description |
|------|-------------|
| `.stackpanel/state/infra-inputs.json` | Serialized module inputs (may include AGE-encrypted values) |
| `.stackpanel/data/infra-outputs.nix` | Outputs from last deploy (loaded at Nix eval time) |

## Generated `alchemy.run.ts`

```typescript
// Generated by stackpanel — do not edit manually
import alchemy from "alchemy";
import Infra from "./src/index.ts";

const app = await alchemy("${projectName}-infra", {
  password: process.env.ALCHEMY_PASSWORD ?? "local-dev-password",
});

// Import modules — each runs its alchemy resources via top-level await
// and default-exports its outputs as Record<string, string>
const awsSecretsOutputs = (await import("./modules/aws-secrets.ts")).default;

// Sync declared outputs to storage backend
await Infra.syncAll({
  "aws-secrets": {
    outputs: awsSecretsOutputs,
    syncKeys: ["roleArn", "kmsKeyArn", "kmsKeyId", "kmsAliasName"],
  },
});

await app.finalize();
```

## Integration

### Stackpanel module registration

```nix
stackpanel.modules.infra = {
  enable = true;
  meta = {
    name = "Infrastructure";
    description = "Alchemy-based infrastructure provisioning";
    icon = "server";
    category = "infrastructure";
  };
  source.type = "builtin";
  features = { files = true; scripts = true; packages = true; };
  tags = [ "infrastructure" "alchemy" "iac" ];
};
```

### Shell scripts

| Script | Description |
|--------|-------------|
| `infra:deploy` | `cd ${output-dir} && bunx alchemy deploy` |
| `infra:destroy` | `cd ${output-dir} && bunx alchemy destroy` |
| `infra:dev` | `cd ${output-dir} && bunx alchemy dev` |
| `infra:pull-outputs` | Read from storage backend, write `.stackpanel/data/infra-outputs.nix` |

### Devshell environment

```nix
stackpanel.devshell.env = {
  STACKPANEL_INFRA_INPUTS = "${stateDir}/infra-inputs.json";
  # AGE key already set by secrets subsystem
};
```

### Agent serialization

```nix
stackpanel.serializable.infra = {
  inherit (cfg) enable framework output-dir key-format;
  storage-backend = { inherit (cfg.storage-backend) type; };
  modules = mapAttrs (id: mod: {
    inherit (mod) name description;
    outputs = mapAttrs (k: v: { inherit (v) description sensitive sync; }) mod.outputs;
  }) cfg.modules;
};
```

## Migration from SST

The `aws-secrets` infra module replaces `stackpanel.sst` for OIDC/IAM/KMS provisioning:

| SST option | Infra equivalent |
|------------|------------------|
| `stackpanel.sst.enable` | `stackpanel.infra.aws.secrets.enable` |
| `stackpanel.sst.region` | `stackpanel.infra.aws.secrets.region` |
| `stackpanel.sst.account-id` | `stackpanel.infra.aws.secrets.account-id` |
| `stackpanel.sst.kms.*` | `stackpanel.infra.aws.secrets.kms.*` |
| `stackpanel.sst.iam.*` | `stackpanel.infra.aws.secrets.iam.*` |
| `stackpanel.sst.oidc.*` | `stackpanel.infra.aws.secrets.oidc.*` |

The SST module (`nix/stackpanel/sst/`) remains untouched for backward compatibility.

## Implementation Order

1. `nix/stackpanel/infra/default.nix` — module aggregator
2. `nix/stackpanel/infra/options.nix` — core options + outputs stub
3. `nix/stackpanel/infra/codegen.nix` — code generation (Infra class, orchestrator, static libs, package.json)
4. `nix/stackpanel/infra/modules/aws-secrets/module.nix` — Nix options + registration
5. `nix/stackpanel/infra/modules/aws-secrets/index.ts` — alchemy implementation
6. `nix/stackpanel/default.nix` — add `./infra` to imports
7. Integration — scripts, module registration, serialization, MOTD
8. Test — Nix evaluation with sample config
