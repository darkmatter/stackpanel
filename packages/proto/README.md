# Proto Package

Protocol Buffer schemas for Stack, generated from Nix definitions.

## Architecture

```
nix/stackpanel/db/schemas/*.proto.nix   →   packages/proto/proto/*.proto   →   packages/proto/gen/
         (source of truth)                      (generated protos)              (generated code)
```

Nix defines the database entity protos. Agent service definitions under `proto/` are handwritten; Buf generates bindings for both. Module settings are described by runtime SpFields, not per-module proto files.

`nix/stackpanel/db/schemas/modules.proto.nix` defines the module data messages and renders `proto/stackpanel/agent/v1/module_data.proto`. The handwritten `module.proto` imports that model for `ModuleService`, including its project-scoped `GetModuleOutputs` RPC.

The v1 TypeScript descriptors are public at `@stackpanel/proto/agent/v1/*` (for example, `ModuleService` from `@stackpanel/proto/agent/v1/module`). `generate.sh buf` runs both templates: `buf.gen.yaml` generates ES and Go bindings, while `buf.gen.legacy.yaml` generates JSON schemas and protobuf-ts bindings only for pre-v1 files.

## Quick Start

```bash
# From repo root (recommended; runs in devshell)
nix develop -c ./packages/proto/generate.sh

# Or, inside the devshell:
./generate.sh
./generate.sh proto   # Generate .proto files from Nix
./generate.sh buf     # Run buf generate
./generate.sh clean   # Remove generated bindings; keep proto inputs and package metadata
```

## Creating a New Schema

1. Copy the template:
   ```bash
   cp ../../nix/stackpanel/db/schemas/_template.proto.nix \
      ../../nix/stackpanel/db/schemas/myentity.proto.nix
   ```

2. Edit the schema (see template for examples)

3. Generate:
   ```bash
   nix develop -c ./packages/proto/generate.sh
   ```

## Schema Syntax

Schemas are defined in Nix using the `proto` library:

```nix
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "myentity.proto";
  package = "stack.db";

  messages = {
    MyEntity = proto.mkMessage {
      name = "MyEntity";
      description = "My entity description";
      fields = {
        # proto.<type> <field_number> "description"
        name = proto.string 1 "Display name";
        count = proto.int32 2 "Item count";
        enabled = proto.optional (proto.bool 3 "Is enabled");
        tags = proto.repeated (proto.string 4 "Tags");
        metadata = proto.map "string" "string" 5 "Key-value metadata";
      };
    };
  };

  enums = {
    Status = proto.mkEnum {
      name = "Status";
      values = ["STATUS_UNSPECIFIED" "STATUS_ACTIVE" "STATUS_INACTIVE"];
    };
  };
}
```

### Field Numbers

**Field numbers are required and must be explicit.** This ensures protobuf wire compatibility.

Rules:
- Numbers must be unique within a message
- Numbers 1-15 use 1 byte (use for frequently-accessed fields)
- Numbers 16-2047 use 2 bytes
- Never reuse a number after deleting a field
- Reserved: 19000-19999 (protobuf internal)

### Type Reference

| Constructor | Proto Type | Example |
|-------------|------------|---------|
| `proto.string n "desc"` | `string` | `proto.string 1 "Name"` |
| `proto.int32 n "desc"` | `int32` | `proto.int32 2 "Count"` |
| `proto.int64 n "desc"` | `int64` | `proto.int64 3 "Big count"` |
| `proto.uint32 n "desc"` | `uint32` | `proto.uint32 4 "Positive"` |
| `proto.uint64 n "desc"` | `uint64` | `proto.uint64 5 "Big positive"` |
| `proto.bool n "desc"` | `bool` | `proto.bool 6 "Enabled"` |
| `proto.double n "desc"` | `double` | `proto.double 7 "Score"` |
| `proto.float n "desc"` | `float` | `proto.float 8 "Rating"` |
| `proto.bytes n "desc"` | `bytes` | `proto.bytes 9 "Data"` |
| `proto.optional field` | `optional T` | `proto.optional (proto.string 1 "x")` |
| `proto.repeated field` | `repeated T` | `proto.repeated (proto.string 1 "x")` |
| `proto.map "K" "V" n "desc"` | `map<K, V>` | `proto.map "string" "int32" 1 "x"` |
| `proto.message "T" n "desc"` | `T` | `proto.message "User" 1 "Owner"` |

## Generated Output

After running `./packages/proto/generate.sh` (in devshell):

```
packages/proto/
├── proto/           # Entity protos and handwritten RPC definitions
├── gen/
│   ├── gopb/        # Go messages and Connect clients/handlers
│   ├── json/        # Database and unversioned agent JSON schemas
│   └── ts/          # TypeScript bindings, ES descriptors and Connect Query
└── ...
```

## Buf Configuration

- `buf.yaml` - Module definition and lint rules
- `buf.gen.yaml` - Code generation plugins

### Adding Plugins

Edit `buf.gen.yaml` to add more generators:

```yaml
plugins:
  # Connect-RPC for TypeScript
  - remote: buf.build/connectrpc/es
    out: gen/connect-ts

  # gRPC for Go
  - remote: buf.build/grpc/go
    out: gen/go
    opt: paths=source_relative

  # Drizzle ORM schemas
  - local: protoc-gen-drizzle
    out: gen/drizzle
```

See [buf.build/plugins](https://buf.build/plugins) for available plugins.

## Linting

```bash
buf lint
```

## Breaking Change Detection

```bash
buf breaking --against '.git#branch=main'
```
