# Design: Machine Provisioning

**Status:** Draft
**Date:** 2026-03-21

---

## 1. Framing: Provisioning vs. Deployment

These are distinct operations that are easy to conflate:

| Operation | Tool | Frequency | Effect |
|---|---|---|---|
| **Provisioning** | `nixos-anywhere` | Once per machine lifetime | Installs NixOS from scratch; destructive |
| **Deployment** | `colmena apply`, `nixos-rebuild switch` | Every release | Pushes a new config to a running machine; non-destructive |

Conflating them under `stackpanel deploy provision` obscures this distinction and buries a consequential, dangerous operation inside a subcommand of a routine one.

**Recommendation: `stackpanel provision` as a top-level command**, parallel to `stackpanel deploy`.

This matches how operators think:
- "I need to provision a new server" → `stackpanel provision`
- "I need to release my app" → `stackpanel deploy my-api`

---

## 2. The Missing Piece: Disk Partitioning

Before addressing the items raised, there is a significant gap not yet mentioned: **`nixos-anywhere` requires a disk partitioning specification to do a full install from scratch**.

`nixos-anywhere` uses [disko](https://github.com/nix-community/disko) to declare and execute disk partitioning. Without it, it cannot install NixOS on a bare machine.

There are two paths:

| Path | Flag | When to use |
|---|---|---|
| **No reformatting** | (default) | Cloud VM already has a partition layout (Hetzner, Vultr, etc.) |
| **Disko layout** | `--format` | Bare metal or VMs where you control partitioning |

**Recommendation for v1**: Default to no reformatting. This covers the most common case (cloud VPS providers where you SSH into the rescue system or an existing Linux install). Opt into disk formatting with `--format`, which requires a `diskLayout` in the machine config.

The CLI output should be explicit: if `--format` is passed but no `diskLayout` is configured, fail early with a clear message: "Pass `diskLayout` in the machine config or provide a disko file via --disk-layout."

---

## 3. Install Target vs. Final Host

The `host` field in `deployment.machines` is the **permanent** IP/hostname used for ongoing `colmena apply` and `nixos-rebuild` deployments. During provisioning, the machine may be reachable at a *different* address:

| Scenario | Install target | Final host | Match? |
|---|---|---|---|
| Cloud VM (static IP) | same IP | `host` in config | ✓ same |
| Hetzner rescue system | rescue IP | `host` in config | ✓ same (IP is static) |
| Bare metal, DHCP boot | DHCP temp IP | permanent static IP | ✗ different |
| Hostname not yet in DNS | IP | `prod.example.com` | ✗ different |

**Recommendation**: Use `host` from config as the install target by default, with an explicit `--install-target` override for cases where they differ. The flag name `--install-target` is clearer than `--ip`, which is ambiguous about whether it is temporary or permanent.

---

## 4. Hardware Configuration Generation

`nixos-anywhere` supports `--generate-hardware-config <generator> <dest-dir>`. After installing NixOS, it SSHes back into the newly-installed machine, runs the generator (typically `nixos-generate-config`), and downloads the output locally.

This is the critical post-provisioning step: without `hardware-configuration.nix`, the machine's NixOS config uses stub defaults (`mkDefault` values for boot loader and filesystems). Once the hardware config is committed to the repo and `config.nix` updated, a `colmena apply` applies the correct, hardware-aware config.

### Hardware config path convention

```
.stackpanel/hardware/<machine-name>/hardware-configuration.nix
```

This directory is gitignored by default (generated files). After generation and inspection, the user commits the file manually — hardware configs should be reviewed before being committed, since they describe disk layout, kernel modules, and filesystem UUIDs.

### The two-step dance

```
1. stackpanel provision prod-server
     → nixos-anywhere installs NixOS using baseMods stubs (mkDefault grub/ext4)
     → hardware-configuration.nix generated to .stackpanel/hardware/prod-server/

2. User reviews and commits .stackpanel/hardware/prod-server/hardware-configuration.nix
     → Updates config.nix: hardwareConfig = ./.stackpanel/hardware/prod-server/hardware-configuration.nix;
     → git commit

3. stackpanel deploy my-api  (or colmena apply --on prod-server)
     → Redeploys with full hardware-aware NixOS config
```

The CLI should communicate this explicitly after a successful provision:

```
✓ Provisioned prod-server

Generated hardware config:
  .stackpanel/hardware/prod-server/hardware-configuration.nix

Next steps:
  1. Review the generated hardware config
  2. Add it to config.nix:
       hardwareConfig = ./.stackpanel/hardware/prod-server/hardware-configuration.nix;
  3. Commit and run: stackpanel deploy my-api
```

---

## 5. Command Design

### `stackpanel provision` (new top-level)

```
stackpanel provision                         List machines with provisioning status
stackpanel provision <machine>               Provision a machine defined in config
stackpanel provision <machine> --install-target <ip>   Override install-time IP
stackpanel provision <machine> --format                Format disk using machine's diskLayout (default: no reformatting)
stackpanel provision <machine> --no-hardware-config    Skip hardware config generation
stackpanel provision <machine> --dry-run     Print nixos-anywhere command, do not run
stackpanel provision <machine> --reprovision Allow re-provisioning an already-provisioned machine
```

New machine mode (machine not yet in `config.nix`):

```
stackpanel provision --new <name> --host <ip> [--user root] [--system x86_64-linux]
```

This creates a minimal machine entry in `config.nix` and then provisions. `--host` sets both the install target and the permanent `host` value in config.

### `stackpanel deploy` (enhanced listing)

`stackpanel deploy` with no arguments currently lists only apps. It should show **both machines and apps**, giving operators a complete picture of infrastructure state:

```
Machines:
  prod-server     49.13.150.192   provisioned 2026-03-15   hardware-config ✓
  staging-server  10.0.0.5        not provisioned

Deployments:
  docs            colmena → prod-server   last: 2026-03-20
  stackpanel-go   colmena → prod-server   never deployed
```

A machine that is not provisioned and has no hardware config is a natural prompt to run `stackpanel provision <name>`.

---

## 6. State Tracking

Introduce `.stackpanel/state/machines.json`, separate from `deployments.json` (which tracks per-app deploy history). Machines and apps have different lifecycles and different operators.

```json
{
  "prod-server": {
    "provisionedAt": "2026-03-15T14:30:00Z",
    "installTarget": "49.13.150.192",
    "hardwareConfigGenerated": true,
    "hardwareConfigPath": ".stackpanel/hardware/prod-server/hardware-configuration.nix",
    "nixRevision": "abc1234"
  }
}
```

| Field | Purpose |
|---|---|
| `provisionedAt` | When the last successful provision ran |
| `installTarget` | The IP/host used during provisioning (may differ from `host` in config) |
| `hardwareConfigGenerated` | Whether the hardware config was downloaded successfully |
| `hardwareConfigPath` | Local path where the hardware config was written |
| `nixRevision` | Git revision of the flake at provision time |

`stackpanel deploy status` (and the listing output) reads this file to determine per-machine provisioning state.

---

## 7. Re-provisioning Guard

Provisioning is destructive. Running `nixos-anywhere` on a live machine will wipe its disk (unless `--no-reformat`). The CLI must guard against accidental re-provisioning:

- **By default**: refuse if `machines.json` shows the machine was already provisioned.
- **Override**: require explicit `--reprovision` flag.
- **Output**: print a clear warning before refusing:

```
✗ prod-server was already provisioned on 2026-03-15.
  Re-provisioning will format the disk and erase all data.
  Pass --reprovision to proceed, or use `stackpanel deploy` for a non-destructive update.
```

---

## 8. `deployment.machines` Schema Additions

Two new fields on the machines submodule:

```nix
diskLayout = lib.mkOption {
  type = lib.types.nullOr lib.types.path;
  default = null;
  description = ''
    Path to a disko Nix file declaring the disk partition layout.
    Required for bare-metal provisioning where you control partitioning.
    If null, nixos-anywhere runs with --no-reformat (assumes existing partition layout).
  '';
  example = ./hardware/prod-server/disk-config.nix;
};
```

The existing `hardwareConfig` option (already implemented) is set post-provisioning. `diskLayout` is used during provisioning. These are distinct concerns: `diskLayout` tells `nixos-anywhere` how to format the disk; `hardwareConfig` describes the resulting hardware to NixOS.

---

## 9. kexec: The Cloud VM Path

Most cloud VPS providers (Hetzner, Vultr, Linode, OVH) do not offer a native NixOS image but do allow SSH access to the running machine. `nixos-anywhere` supports this via kexec: it uploads a NixOS installer kernel and initrd, kexecs into it, and proceeds with installation — no ISO, no rescue boot.

This is the primary path for cloud VMs and requires no special provider support. The operator SSHes into the machine's existing Linux install; `nixos-anywhere` takes it from there.

Constraints:
- Requires ≥512 MB RAM for the kexec initrd (most VMs have ≥1 GB)
- The SSH connection drops during kexec and reconnects to the installer

`nixos-anywhere` handles kexec automatically when the target is not already a NixOS installer. No special flag is needed. The CLI should document this clearly so operators know they do not need to provision a rescue boot.

---

## 10. SSH Host Key Rotation

After provisioning, the machine has a new SSH host key. Any prior `~/.ssh/known_hosts` entry for the machine's IP/hostname will cause failures on subsequent connections.

`nixos-anywhere` handles this for its own connection by disabling strict host checking during install. But subsequent `colmena apply` and `nixos-rebuild switch` will fail with "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED" unless the user updates `known_hosts`.

The CLI should, after successful provisioning:
1. Run `ssh-keyscan <host>` to fetch the new host key.
2. Either update `~/.ssh/known_hosts` automatically, or print the `ssh-keyscan` output with instructions.

This is a common source of confusion for first-time provisioners.

---

## 11. Secrets Bootstrapping (Out of Scope for v1)

For machines that use sops-nix, the machine needs its SSH host key enrolled in `.sops.yaml` before it can decrypt secrets. The host key is generated during provisioning and is not known beforehand.

The full flow:
```
1. Provision machine  →  machine gets SSH host key (generated by NixOS)
2. Fetch host key from machine:  ssh-keyscan -t ed25519 prod-server
3. Add key to .sops.yaml as a recipient
4. Re-encrypt secrets:  sops updatekeys .stackpanel/secrets/prod.yaml
5. Commit .sops.yaml and re-encrypted secrets
6. Deploy:  stackpanel deploy my-api
   (sops-nix can now decrypt secrets on the machine)
```

Steps 2–5 are currently manual. This could be partially automated post-provisioning, but involves git commits and secret re-encryption — significant automation with meaningful risk. Leave as documented manual steps for v1.

---

## 12. Proposed Implementation

### Phase 1: Core provisioning

- [ ] `stackpanel provision` as a top-level command (in `provision.go`, not `deploy.go`)
- [ ] Read machine config from `deployment.machines` (host, user, system)
- [ ] `--install-target` override
- [ ] No reformatting by default; `--format` opts into disko; `diskLayout` wires disko into nixosConfigurations
- [ ] Hardware config generation to `.stackpanel/hardware/<machine>/`
- [ ] Post-provision output: next-steps instructions
- [ ] `.stackpanel/state/machines.json` state tracking
- [ ] Re-provision guard with `--reprovision` override
- [ ] `stackpanel deploy` listing shows machine provisioning status

### Phase 2: New machine creation

- [ ] `--new` flag: creates minimal machine entry in `config.nix`
- [ ] Programmatic `config.nix` edit (following the existing "machine writes" pattern)
- [ ] Auto-sets `hardwareConfig` path in the new entry after generation

### Phase 3: Convenience

- [ ] SSH host key rotation: auto-update `~/.ssh/known_hosts` post-provision
- [ ] `diskLayout` support for bare-metal with explicit disko configs
- [ ] Guidance for sops-nix key enrollment (print instructions, not automate)

---

## 13. Open Questions

**Q1: Should `--new` auto-edit `config.nix`?**

The infrastructure exists and is already proven: `internal/agent/server/agenix.go:updateVariableEntry` uses exactly this pattern today for `variables.nix` — `nix eval --json -f <file>` to read, Go map modification, then `pkg/nix/serialize.go:SerializeWithSections` (which calls `nixfmt`) to write back. `config.nix` is the same shape (a plain attrset), so the same approach applies directly.

The one gap is Nix path literals: `nix eval --json` resolves `./hardware/prod.nix` to an absolute string, which serializes back as a quoted string rather than a path literal. This can be solved with a **tagged object convention** throughout the JSON round-trip:

- **Nix side** — a `wrapPaths` helper used when evaluating for editing (not for regular config reads):
  ```nix
  wrapPaths = v:
    if      builtins.isPath  v then { __nixPath = v; }
    else if builtins.isAttrs v then builtins.mapAttrs (_: wrapPaths) v
    else if builtins.isList  v then map wrapPaths v
    else v;
  ```
  `builtins.isPath` distinguishes path literals from strings. After `--json`, this produces `{"__nixPath": "/abs/path/to/hardware/prod.nix"}`.

- **Go side** — a `NixPath` type in `pkg/nix` with custom marshaling:
  ```go
  type NixPath string

  func (p NixPath) MarshalJSON() ([]byte, error) {
      return json.Marshal(map[string]string{"__nixPath": string(p)})
  }
  func (p *NixPath) UnmarshalJSON(data []byte) error {
      var m map[string]string
      if err := json.Unmarshal(data, &m); err != nil { return err }
      *p = NixPath(m["__nixPath"])
      return nil
  }
  ```
  When reading, the absolute path is converted to a project-relative path (`./hardware/prod.nix`). When serializing back to Nix, `serialize.go` emits it as an unquoted path literal.

The round-trip then preserves path types end-to-end:

```
./hardware/prod.nix  →  {"__nixPath": "/abs/.../prod.nix"}  →  NixPath("./hardware/prod.nix")  →  ./hardware/prod.nix
```

The `__nixPath` convention follows Nix's own `__toString` pattern for meta-attributes and is naturally extensible — e.g. `{"__nixLiteral": "lib.mkDefault 42"}` for raw Nix expressions if ever needed.

With this in place, both the machine creation step and the `hardwareConfig` update step can be fully automated via the same JSON round-trip.

**Q2: Should `hardwareConfig` be auto-committed?**

No. The CLI writes the file and updates `config.nix`; the user reviews and commits. Hardware configs contain disk UUIDs, kernel modules, and hardware quirks that warrant inspection before being committed to the repo.

**Q3: Where should `diskLayout` files live?**

`.stackpanel/hardware/<machine>/disk-config.nix`, alongside `hardware-configuration.nix`. Keeps all machine-specific generated files together under `.stackpanel/hardware/`.

**Q4: Should `stackpanel provision` (no args) be the status listing?**

Yes. Consistent with the no-args listing pattern used by `stackpanel deploy`. The output is clearly read-only, so there is no risk of confusion with the destructive provisioning operation.

**Q5: Multi-architecture**

The `system` field in machine config controls the `nixpkgs.lib.nixosSystem` system. An ARM64 machine (Ampere, AWS Graviton) would need `aarch64-linux`. Cross-compilation from x86_64 is supported by Nix but requires `nixpkgs.crossSystem`. This is already handled correctly by the per-machine `nodeNixpkgs` in `mkHive` — no extra work needed, but worth testing.
