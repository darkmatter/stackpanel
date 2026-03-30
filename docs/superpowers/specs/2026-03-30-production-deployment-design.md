# Production Deployment Architecture

> **Status:** Draft — 2026-03-30
>
> **Scope:** Deploy `stackpanel.com` and `docs.stackpanel.com` to Cloudflare Workers; deploy long-running API services on NixOS microVMs hosted on OVH US-West and Hetzner Helsinki; geo-route API traffic via Cloudflare; run self-hosted PostgreSQL + Redis on each host with cross-site replication.

---

## Problem

Stackpanel currently has no cohesive production deployment:

- `stackpanel.com` (web app) is configured for AWS EC2 but not reliably deployed to Cloudflare Workers where it belongs.
- `docs.stackpanel.com` is configured for Alchemy/Cloudflare but not deployed end-to-end.
- There is no production API service for long-running backend work. (The Go agent is a local per-user daemon, not a production service.)
- No geo-routing exists — a single region serves all traffic.
- The existing bare-metal machines (OVH, Hetzner) already run microvm.nix VMs (see `~/git/darkmatter/infra`), but the stackpanel project does not yet use them for production workloads.
- There is no self-hosted database or cache; Neon Serverless is the only database path.

---

## Architecture Model: Agent vs API

**stackpanel agent** is a per-user local daemon — architecturally similar to Drizzle's `local.drizzle.studio`. The user runs `stackpanel agent` on their own machine (eventually installed as a launchctl service on macOS). The web app at `local.stackpanel.com` is the same as `stackpanel.com` but with CORS headers pre-configured so the browser can communicate with the local agent at `localhost:9876`.

The **production API** is a separate concern: long-running backend services for features that cannot run inside a user's local agent. This is a new **Bun-based TypeScript worker** (`apps/api/`), not the Go agent binary. The Go agent stays local.

---

## Goals

1. Deploy `stackpanel.com` to Cloudflare Workers globally.
2. Deploy `docs.stackpanel.com` to Cloudflare Workers globally.
3. Scaffold and deploy a new Bun-based API worker (`apps/api/`) on NixOS microVMs:
   - One API microVM on OVH US-West (`ovh-usw-1`).
   - One API microVM on Hetzner Helsinki (`hzcloud-hel-1`).
4. Run self-hosted PostgreSQL + Redis microVMs on each host, with cross-site replication.
5. Geo-route API traffic via Cloudflare Workers: Americas → OVH US-West; Europe/Asia → Hetzner Helsinki.
6. Use the existing Stackpanel deployment system (Alchemy for Cloudflare, Colmena for NixOS) throughout.
7. Use microvm.nix as the VM abstraction layer, following the proven pattern in `~/git/darkmatter/infra/nix/nixos/hosts/ovh-usw-1/system.nix`.

---

## Non-Goals

- Deploying the Go agent to production (it stays local per-user).
- Full multi-tenancy isolation per customer at the VM level.
- Replacing Neon Serverless immediately — self-hosted Postgres is additive and may coexist.
- Building a complete API surface in wave 1 — the Bun worker is a scaffold for future services.

---

## Architecture Overview

```
                         Browser
                            │
              ┌─────────────┴──────────────┐
              │     Cloudflare Edge (CF)    │
              ├────────────────────────────┤
              │  stackpanel.com            │ → CF Worker: web app (TanStack Start)
              │  local.stackpanel.com      │ → same Worker, CORS → localhost agent
              │  docs.stackpanel.com       │ → CF Worker: docs (Fumadocs/Next.js)
              │  api.stackpanel.com        │ → CF geo-router Worker
              └──────────┬────────┬────────┘
                         │        │
              ┌──────────┘        └──────────────┐
              │                                  │
              ▼ Americas                         ▼ Europe / Asia
   ┌─────────────────────────┐       ┌─────────────────────────┐
   │  OVH US-West            │       │  Hetzner Helsinki       │
   │  ovh-usw-1              │       │  hzcloud-hel-1          │
   │  (15.204.104.4)         │       │  (existing/new node)    │
   │  128GB RAM, AMD EPYC    │       │  128GB RAM              │
   │                         │       │                         │
   │  ┌───────────────────┐  │       │  ┌───────────────────┐  │
   │  │ microvm: api      │  │       │  │ microvm: api      │  │
   │  │ 8GB, Bun worker   │  │       │  │ 8GB, Bun worker   │  │
   │  │ :3000 (HTTP)      │  │       │  │ :3000 (HTTP)      │  │
   │  └───────────────────┘  │       │  └───────────────────┘  │
   │  ┌───────────────────┐  │       │  ┌───────────────────┐  │
   │  │ microvm: db       │  │       │  │ microvm: db       │  │
   │  │ 8GB, PG + Redis   │  │       │  │ 8GB, PG + Redis   │  │
   │  │ :5432, :6379      │  │       │  │ :5432, :6379      │  │
   │  └───────────────────┘  │       │  └───────────────────┘  │
   │  Caddy on host :443     │       │  Caddy on host :443     │
   │  TLS → api VM :3000     │       │  TLS → api VM :3000     │
   └─────────────────────────┘       └─────────────────────────┘
              │                                  │
              └─── PG logical replication ───────┘
              └─── Redis replication ────────────┘
```

### local.stackpanel.com

`local.stackpanel.com` serves the exact same Cloudflare Worker as `stackpanel.com`. The difference is CORS: the local variant allows the browser to communicate with the user's local `stackpanel agent` daemon at `localhost:9876`. This is how users interact with their own dev environment from the web Studio UI — same pattern as `local.drizzle.studio`.

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

#### 3a. microvm.nix integration — follow existing infra pattern

The OVH host already runs microvm.nix with a proven pattern in `~/git/darkmatter/infra/nix/nixos/hosts/ovh-usw-1/system.nix`. That config defines:

- TAP+bridge networking (`br-vms` bridge, `10.0.100.0/24` subnet, NAT through host)
- `cloud-hypervisor` hypervisor
- virtiofs shares for `/nix/store` (read-only) and `/var/lib/vm-secrets` (secrets injection)
- `mkVM` helper for consistent VM definitions
- `dnsmasq` for DHCP/DNS on the bridge
- Tailscale on each VM via shared auth key
- systemd services to bridge TAP interfaces after microvm creates them

The stackpanel project should adopt this same pattern. No additional public IPv4 addresses are needed — VMs get private IPs on the bridge, the host's existing public IP handles inbound traffic, and Caddy on the host reverse-proxies to the correct VM port.

#### 3b. Guest VM: API worker

Each API microVM guest runs:

- **Bun-based API worker** (`apps/api/`) — a TypeScript HTTP service scaffolded for future long-running backend features
- **Tailscale** — for inter-VM and management access
- **Minimal NixOS** — standard `vm-general.nix` pattern (ssh, tools, Tailscale)

The API worker is a new app: `apps/api/`. It is a scaffold Bun HTTP server (likely Hono) that responds to health checks and will grow to serve production backend needs. It is NOT the Go agent.

#### 3c. Guest VM: Database + cache

Each host also runs a **db microVM**:

- **PostgreSQL** — self-hosted, with logical replication between the two hosts
- **Redis** — self-hosted, with replication between the two hosts
- **sops-nix secrets** — database passwords, replication credentials

This adds a self-hosted database option alongside the existing Neon Serverless path.

#### 3d. Networking model — TAP + bridge + NAT

Following the proven infra pattern:

- Host creates `br-vms` bridge with `10.0.100.0/24` subnet
- Each VM gets a TAP interface bridged into `br-vms`
- Host runs NAT so VMs can reach the internet
- `dnsmasq` provides DHCP to VMs on the bridge
- External traffic arrives at the host's public IP; Caddy on the host terminates TLS and proxies to the VM's private IP

No additional IPv4 addresses required. The host's domain name resolves to its existing public IP.

#### 3e. VM sizing

Hosts have 128GB RAM each. Generous sizing:

| VM | vCPUs | RAM | Disk | Ports |
|---|---|---|---|---|
| `api` | 4 | 8 GB | 20 GB | 3000 (HTTP) |
| `db` | 8 | 8 GB | 60 GB | 5432 (PG), 6379 (Redis) |

Hypervisor: `cloud-hypervisor` on both hosts (proven in the existing infra config).

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

Secrets are injected into VMs via the existing virtiofs `/var/lib/vm-secrets` → `/run/vm-secrets` pattern (proven in the infra repo). The host decrypts secrets via sops-nix and copies them to the shared mount before VM startup.

Required secrets (new, to be added to SOPS):
- `DATABASE_URL` — self-hosted PG connection string (or Neon fallback)
- `BETTER_AUTH_SECRET` — auth signing secret
- `POLAR_ACCESS_TOKEN` — billing
- `CLOUDFLARE_API_TOKEN` — for Alchemy deploy and Caddy DNS challenge
- `PG_REPLICATION_PASSWORD` — for cross-site PostgreSQL logical replication
- `REDIS_REPLICATION_PASSWORD` — for cross-site Redis replication

---

## microvm.nix Hypervisor Choice

**Decision: `cloud-hypervisor`** — already proven on OVH in the existing infra repo. Both hosts are x86_64 dedicated servers with KVM support.

## Database Replication Strategy

### PostgreSQL: Logical Replication

- OVH US-West runs the **primary** PostgreSQL instance
- Hetzner Helsinki runs a **logical replica** (read-only for local API queries, writable for local-first patterns if needed later)
- Replication over Tailscale (encrypted, no public exposure of PG ports)
- Publications/subscriptions defined via NixOS config

### Redis: Active Replication

- One Redis primary (OVH), one replica (Hetzner Helsinki)
- Connected over Tailscale
- Eventual switch to Redis Cluster if needed, but simple primary/replica is sufficient for wave 1

---

## Implementation Phases

### Phase 1: Cloudflare Workers frontends (stackpanel.com + docs)

- Change web app `deployment.host` from `"aws"` to `"cloudflare"`
- Wire Alchemy config for `stackpanel-web` Worker
- Confirm `stackpanel-docs` Alchemy config
- Deploy both Workers via `just deploy-alchemy` with `STAGE=prod`
- Set Cloudflare DNS: `stackpanel.com` + `docs.stackpanel.com`
- Estimated effort: small (mostly config + a real deploy run)

### Phase 2: Scaffold the Bun API worker (`apps/api/`)

- Create `apps/api/` with a minimal Hono-based Bun HTTP server
- Health check endpoint: `GET /health`
- Placeholder routes for future backend services
- Add to monorepo workspace, Turborepo build config
- Test locally with `bun run dev`

### Phase 3: microvm.nix integration

- Add `microvm` flake input to `flake.nix`
- Create host-side NixOS modules for microvm definitions (following the `mkVM` pattern from `~/git/darkmatter/infra`)
- Define API VM + DB VM per host
- Deploy host configs via Colmena to `ovh-usw-1` (already provisioned)
- Provision `hzcloud-hel-1` if needed → `stackpanel provision`
- Deploy host + VM configs to both machines
- Verify VMs boot, Tailscale connects, and API health check responds

### Phase 4: TLS and certificates

- Set up Caddy on each host to reverse-proxy `:443` → API VM `:3000`
- ACME / Let's Encrypt cert for `api.stackpanel.com` (both hosts serve the same domain via geo-routing)
- Verify HTTPS health endpoints from outside

### Phase 5: Database + cache microVMs

- Define db VMs with PostgreSQL + Redis per host
- Configure PostgreSQL logical replication (OVH primary → Helsinki replica) over Tailscale
- Configure Redis primary/replica over Tailscale
- Update API worker to connect to local PG/Redis VM

### Phase 6: Geo-routing Worker

- Write `packages/infra/api-router/` CF Worker (TypeScript, Hono)
- Deploy via Alchemy to `api.stackpanel.com`
- Bind `API_ORIGIN_OVH` and `API_ORIGIN_HEL` environment variables
- Test geo-routing from Americas and Europe

### Phase 7: Wire web app to geo-routed API

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
