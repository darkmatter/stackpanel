# Production Deployment Architecture

> **Status:** Draft — 2026-03-30
>
> **Scope:** Deploy `stackpanel.com` and `docs.stackpanel.com` to Cloudflare Workers; deploy the stackpanel API on NixOS microVMs hosted on OVH US-West and Hetzner Helsinki; connect them via Cloudflare geo-routing / load balancing.

---

## Problem

Stackpanel currently has no cohesive production deployment:

- `stackpanel.com` (web app) is configured for AWS EC2 but not reliably deployed to Cloudflare Workers where it belongs.
- `docs.stackpanel.com` is configured for Alchemy/Cloudflare but not deployed end-to-end.
- The `stackpanel-go` API agent runs only as a local per-developer daemon; there is no production API node for hosted/team use.
- No geo-routing exists — a single region serves all traffic.
- There is no microvm.nix integration; the existing Helsinki (volt-*) and OVH bare-metal machines are unused for production services.

---

## Goals

1. Deploy `stackpanel.com` to Cloudflare Workers globally.
2. Deploy `docs.stackpanel.com` to Cloudflare Workers globally.
3. Run the Stackpanel API on NixOS microVMs:
   - One microVM on OVH US-West (`ovh-usw-1`).
   - One microVM on Hetzner Helsinki (new dedicated machine or `volt-1`).
4. Geo-route API traffic via Cloudflare Load Balancer: Americas → OVH US-West; Europe/Asia → Hetzner Helsinki.
5. Use the existing Stackpanel deployment system (Alchemy for Cloudflare, Colmena for NixOS) throughout.
6. Use microvm.nix as the VM abstraction layer on each bare-metal host.

---

## Non-Goals

- Replacing the local Go agent with the production API (they coexist: local agent = per-developer, production API = hosted/team service).
- Full multi-tenancy isolation per customer at the VM level.
- Building a new tRPC backend — the production API runs the existing `stackpanel-go` binary in agent mode.
- High-availability database clustering (Neon Serverless handles that).

---

## Architecture Overview

```
                    Browser
                       │
         ┌─────────────┴──────────────┐
         │     Cloudflare Edge (CF)   │
         │  Workers KV / CDN / Proxy  │
         ├────────────────────────────┤
         │   stackpanel.com           │  → CF Worker: web app (TanStack Start)
         │   docs.stackpanel.com      │  → CF Worker: docs (Fumadocs/Next.js)
         │   api.stackpanel.com       │  → CF Load Balancer (geo-routed)
         └──────────┬────────┬────────┘
                    │        │
         ┌──────────┘        └─────────────┐
         │                                 │
         ▼ Americas                        ▼ Europe / Asia
 ┌───────────────────┐            ┌─────────────────────┐
 │  OVH US-West      │            │  Hetzner Helsinki   │
 │  ovh-usw-1        │            │  hzcloud-hel-1      │
 │  (15.204.104.4)   │            │  (new public node)  │
 │                   │            │                     │
 │  ┌─────────────┐  │            │  ┌───────────────┐  │
 │  │ microvm     │  │            │  │ microvm       │  │
 │  │ sp-api-vm   │  │            │  │ sp-api-vm     │  │
 │  │             │  │            │  │               │  │
 │  │ stackpanel  │  │            │  │ stackpanel    │  │
 │  │ agent mode  │  │            │  │ agent mode    │  │
 │  │ :9876       │  │            │  │ :9876         │  │
 │  └──────┬──────┘  │            │  └───────┬───────┘  │
 │         │  Caddy  │            │          │   Caddy  │
 │  :443 ──┘ (TLS)  │            │  :443 ───┘  (TLS)  │
 └───────────────────┘            └─────────────────────┘
                    │                        │
                    └────────────────────────┘
                           Neon PostgreSQL
                      (serverless, accessed
                       via pooler from both)
```

---

## Component Details

### 1. Cloudflare Workers: stackpanel.com

- **App:** `apps/web` (TanStack Start + Vite + `@opennextjs/cloudflare`)
- **Worker name:** `stackpanel-web`
- **Change from current:** Replace `deployment.host = "aws"` with `deployment.host = "cloudflare"` in `.stack/config.nix`.
- **Secrets required:** `DATABASE_URL`, `BETTER_AUTH_SECRET`, `POLAR_ACCESS_TOKEN`
- **Deployment backend:** Alchemy IaC (already wired; just target CF Workers)
- **Domain:** `stackpanel.com` → Cloudflare DNS CNAME to worker

### 2. Cloudflare Workers: docs.stackpanel.com

- **App:** `apps/docs` (Next.js / Fumadocs + `@opennextjs/cloudflare`)
- **Worker name:** `stackpanel-docs`
- **Current state:** Already configured as `deployment.backend = "alchemy"` + `deployment.host = "cloudflare"`. Needs a real deploy run.
- **Domain:** `docs.stackpanel.com` → Cloudflare DNS CNAME to worker

### 3. API microVMs

#### 3a. microvm.nix integration

Add `microvm` to `flake.nix` inputs:

```nix
microvm = {
  url = "github:astro/microvm.nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

The host machine (OVH or Hetzner bare-metal) becomes a **microvm host** via the NixOS module:

```nix
microvm.host  # Host-side: manages VMs via systemd services
```

The guest VM is defined as a **microvm guest** NixOS configuration:

```nix
microvm.vms.sp-api-vm = {
  # NixOS module for the API VM
};
```

#### 3b. Guest VM NixOS configuration

Each microVM guest runs:

- **stackpanel-go in agent mode** — the production API binary
- **Caddy** — TLS termination, reverse proxy to agent port 9876
- **sops-nix** — decrypt secrets (DATABASE_URL, BETTER_AUTH_SECRET, Cloudflare tokens)
- **Minimal NixOS** — no desktop, no dev tooling

The guest NixOS config is defined at:
- `nix/hosts/sp-api-vm/default.nix` — shared guest config
- `nix/hosts/ovh-usw-1/microvm.nix` — OVH host + vm override
- `nix/hosts/hzcloud-hel-1/microvm.nix` — Hetzner Helsinki host + vm override

#### 3c. Networking model

- **Host option A (recommended): macvtap networking**
  - The VM gets a real MAC + IP on the host's public-facing network segment
  - The host routes traffic directly (no NAT)
  - Caddy inside the VM terminates TLS on port 443

- **Host option B: TAP + NAT**
  - VM has a private IP (e.g., 10.0.0.2)
  - Host NATs and forwards port 443 → VM:443
  - Simpler but adds an extra hop

Recommendation: **macvtap** — makes the VM a first-class internet endpoint with its own IP. OVH and Hetzner both support additional IPs / virtual MACs.

#### 3d. API VM sizing

- **Hypervisor:** `cloud-hypervisor` (best for x86_64 production VMs with virtio)
- **vCPUs:** 2 per VM (host can spare these on OVH/Hetzner dedicated)
- **RAM:** 1 GB per VM (stackpanel-go agent + Caddy is lightweight)
- **Disk:** 10 GB virtio-blk backed by a file on the host

### 4. Cloudflare Load Balancer (geo-routing)

- **Pool A — Americas:** Origin = OVH US-West public IP, port 443
- **Pool B — Europe/Asia:** Origin = Hetzner Helsinki public IP, port 443
- **Health check:** HTTPS GET `/health` on each origin (stackpanel-go exposes this — confirm or add)
- **Steering policy:** Geo-steering — Americas → Pool A, Europe/Asia → Pool B, with cross-pool failover
- **DNS:** `api.stackpanel.com` CNAME to the LB endpoint
- **TLS:** End-to-end — CF terminates inbound TLS, re-encrypts to origin with trusted cert (Let's Encrypt from step-ca or ACME)

Alternatively, use **Cloudflare Workers Smart Routing**:
- A thin Worker at `api.stackpanel.com` receives the request, reads `CF-IPCountry`, and proxies to the nearest origin using `fetch()`
- Simpler than the LB product, lower cost, more control

**Recommendation: Workers-based geo-routing** — zero additional CF product cost, fully programmable, integrates with the existing Alchemy infra code.

```typescript
// packages/infra/api-router.ts (deployed as CF Worker)
export default {
  fetch(request: Request, env: Env) {
    const country = request.headers.get('CF-IPCountry') ?? 'US';
    const isEurope = ['GB','DE','FR','NL','FI','SE','NO','PL','ES','IT', ...].includes(country);
    const origin = isEurope ? env.API_ORIGIN_HEL : env.API_ORIGIN_OVH;
    const url = new URL(request.url);
    url.host = origin;
    return fetch(new Request(url.toString(), request));
  }
}
```

This is simple, cost-free, and gives full control over the routing policy.

---

## Deployment System Integration

### Nix config additions (`.stack/config.nix`)

```nix
# Change web deployment target
apps.web.deployment.host = "cloudflare";  # was "aws"

# Add Helsinki API machine
deployment.machines.hzcloud-hel-1 = {
  host = "<hetzner-hel-public-ip>";
  user = "root";
  system = "x86_64-linux";
  authorizedKeys = [ "ssh-ed25519 ..." ];
};

# API microVM app (future: targets both machines)
apps.stackpanel-api-vm = {
  deployment = {
    enable = true;
    backend = "colmena";
    targets = [ "ovh-usw-1" "hzcloud-hel-1" ];
  };
};
```

### Provision flow

1. `stackpanel provision hzcloud-hel-1` — install NixOS on new dedicated Hetzner Helsinki machine (using existing provision command + `--format` for disko)
2. Deploy microvm host config to both machines via Colmena
3. microvm.nix starts the guest VM as a systemd service on each host
4. Caddy in each VM acquires a Let's Encrypt TLS cert for `api.stackpanel.com` (or step-ca issued cert)
5. Cloudflare Worker geo-router deployed via Alchemy, pointing to both API origins

### Deploy flow (ongoing)

```bash
# Deploy Cloudflare Workers
just deploy-alchemy           # deploys web + docs Workers + api-router Worker

# Deploy API VM updates to both hosts via Colmena
stackpanel deploy sp-api-vm --target ovh-usw-1
stackpanel deploy sp-api-vm --target hzcloud-hel-1
```

---

## Secrets

The API microVM needs access to production secrets. Using **sops-nix** on the NixOS guest:

- The host machine's SSH host key (after provisioning) is enrolled in `.sops.yaml`
- The VM's AGE key (derived or passed from host) is also enrolled
- sops-nix decrypts `.stack/secrets/vars/prod.sops.yaml` at activation time
- Secrets exposed as environment files read by the `stackpanel-go` agent

Required secrets (new, to be added):
- `DATABASE_URL` — Neon PostgreSQL connection string (prod pool)
- `BETTER_AUTH_SECRET` — auth signing secret
- `POLAR_ACCESS_TOKEN` — billing
- `CLOUDFLARE_API_TOKEN` — for Caddy DNS challenge or Alchemy
- `AGENT_JWT_SECRET` — stackpanel agent JWT signing key (if in hosted mode)

---

## microvm.nix Hypervisor Choice

| Option | Pros | Cons |
|---|---|---|
| `qemu` | Most compatible, broad hardware | Slightly heavier |
| `cloud-hypervisor` | Fast, production-grade, virtio | Needs Intel TDX or KVM |
| `firecracker` | AWS Lambda-proven, ultra-fast startup | No PCI, limited virtio devices |
| `kvmtool` | Simple | Minimal community |

**Recommendation: `cloud-hypervisor`** for both OVH and Hetzner. Both are x86_64 dedicated servers with KVM support. cloud-hypervisor is already used in production by major cloud providers and is the most sensible choice for a small long-running service VM.

---

## Implementation Phases

### Phase 1: Cloudflare Workers frontends (stackpanel.com + docs)

- Change web app `deployment.host` from `"aws"` to `"cloudflare"`
- Wire Alchemy config for `stackpanel-web` Worker
- Confirm `stackpanel-docs` Alchemy config
- Deploy both Workers via `just deploy-alchemy` with `STAGE=prod`
- Set Cloudflare DNS: `stackpanel.com` + `docs.stackpanel.com`
- Estimated effort: small (mostly config + a real deploy run)

### Phase 2: microvm.nix integration

- Add `microvm` flake input to `flake.nix`
- Create `nix/hosts/sp-api-vm/default.nix` — the shared guest NixOS config
- Create host-side NixOS modules for `ovh-usw-1` and `hzcloud-hel-1`
- Define `stackpanel-api-vm` app in `.stack/config.nix` targeting both machines
- Deploy host configs via Colmena to `ovh-usw-1` (already provisioned)
- Provision `hzcloud-hel-1` (new Helsinki machine) → install NixOS via `stackpanel provision`
- Deploy host + VM configs to both machines
- Verify VM boots and `stackpanel-go` agent is reachable on each host

### Phase 3: TLS and certificates

- Set up Caddy inside each VM to reverse-proxy `:443` → `localhost:9876`
- ACME / Let's Encrypt cert for `api-usw.stackpanel.com` and `api-hel.stackpanel.com`
- Or: use the existing step-ca integration in the project for internal TLS
- Verify HTTPS health endpoints from outside

### Phase 4: Geo-routing Worker

- Write `packages/infra/api-router/` CF Worker (TypeScript, Hono)
- Deploy via Alchemy to `api.stackpanel.com`
- Bind `API_ORIGIN_OVH` and `API_ORIGIN_HEL` environment variables
- Test geo-routing from Americas and Europe

### Phase 5: Wire web app to geo-routed API

- Update web app config: `STACKPANEL_API_URL = "https://api.stackpanel.com"`
- Test connectivity: web app → Cloudflare Worker router → nearest API VM
- Smoke test auth flow, tRPC calls, Studio features

---

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| microvm.nix networking complexity on OVH (IP allocation) | Use TAP+NAT fallback if macvtap not possible; OVH supports additional MACs |
| Hetzner Helsinki machine needs provisioning (no hardware config yet) | Use `stackpanel provision hzcloud-hel-1 --format` with disko |
| sops-nix requires host SSH key enrolled before first deploy | Enroll key right after `stackpanel provision` completes |
| API Worker routing adds latency | CF Worker overhead is ~1ms; negligible |
| VM migration / state (if VM crashes) | microvm systemd service auto-restarts; stateless API VM (no local state) |
| DNS propagation during cutover | Use low TTL (60s) before cutover; roll back by removing CNAME |

---

## Success Criteria

- [ ] `stackpanel.com` loads from Cloudflare Workers globally
- [ ] `docs.stackpanel.com` loads from Cloudflare Workers globally
- [ ] `api.stackpanel.com` routes to OVH from US and Hetzner Helsinki from EU
- [ ] Both API VMs respond to health checks
- [ ] Auth flow works end-to-end (login → token → Agent API)
- [ ] `stackpanel provision` and `stackpanel deploy` are used throughout — no one-off scripts
- [ ] All secrets are SOPS-encrypted; no plaintext in git

---

## Superseded by This Spec

None — this is a new architectural document. Related docs:
- `docs/superpowers/specs/2026-03-28-deployment-system.md` — deployment system canonical spec
- `docs/design/deploy-command.md` — historical (superseded)
