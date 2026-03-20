# `@stack/sdk`

Stack SDK package for reusable TypeScript utilities.

This package is **not code-generated** and is intended to provide stable, hand-authored helpers you can use across Stack apps and modules.

## What it currently exports

- `@stack/sdk/sops`
  - `AlchemyFile` (re-export from `alchemy/fs`)
  - `AlchemyFileModule`
  - `createAlchemyFileModule`
  - `createDefaultSopsResolver`
  - `moduleDir`
  - related TypeScript types

## Install / workspace usage

In this monorepo, consume it via workspace dependency:

```json
{
  "dependencies": {
    "@stack/sdk": "workspace:*"
  }
}
```

## File module overview

The file module combines:

1. **Alchemy FS resource support** via `AlchemyFile` (create/update/delete files)
2. **SOPS ref reading** via `sops-age` for refs like:
   - `ref+sops://.stack/secrets/vars/common.sops.yaml#/API_KEY`
3. **Alchemy-native secret wrapping** via:
   - `secret(value)` → `alchemy.secret(value)`
   - `readSecret(pathOrRef)` → read + wrap as secret

## Basic usage

```ts
import { AlchemyFile, createAlchemyFileModule } from "@stack/sdk/sops";

const files = createAlchemyFileModule();

// Manage files with Alchemy FS
await AlchemyFile("config.txt", {
  path: "config.txt",
  content: "hello from sdk",
});

// Read plain file
const packageJson = await files.readFile("package.json");

// Read secret from SOPS ref (decrypted via sops-age)
const apiToken = await files.readFile(
  "ref+sops://.stack/secrets/vars/common.sops.yaml#/cloudflare-api-token",
);

// Wrap as native Alchemy secret
const apiTokenSecret = await files.readSecret(
  "ref+sops://.stack/secrets/vars/common.sops.yaml#/cloudflare-api-token",
);

// Wrap an existing plaintext value as a secret
const dbPasswordSecret = files.secret("local-dev-password");
```

## `createAlchemyFileModule` options

```ts
type AlchemyFileModuleOptions = {
  rootDir?: string;
  readPlainFile?: (filePath: string) => Promise<string>;
  secretKey?: string;
};
```

- `rootDir`: Base directory for resolving relative `ref+sops://...` file paths.
- `readPlainFile`: Override plain file reading behavior.
- `secretKey`: Optional AGE private key content passed directly to `sops-age`.

If `secretKey` is omitted, `sops-age` uses its standard environment-based key discovery (`SOPS_AGE_KEY_FILE`, `SOPS_AGE_KEY`, `SOPS_AGE_KEY_CMD`).

## Error behavior

The SDK throws descriptive errors when:

- A SOPS ref format is invalid
- JSON pointer path is not found
- Decryption fails (missing or invalid AGE key material)
- A resolved SOPS value is empty/null

## Notes

- This package is ESM (`"type": "module"`).
- `AlchemyFileModule` is intended for runtime usage in Node/Bun contexts.
- Prefer `readSecret()` when passing secret values into Alchemy resource configs.