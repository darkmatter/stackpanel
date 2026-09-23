# 0004 — The local agent API is Connect, organized as versioned domain services

- **Status**: Accepted
- **Date**: 2026-09-23
- **Related**: [ADR 0005](./0005-per-request-project-selection.md),
  darkmatter org ADR-0003 (protobuf is the source of truth; Connect is the
  default transport)

## Context

The Studio talks to the local Go agent (`stack agent`, port 9876) over two
transports at once:

- **REST/JSON** — ~60 hand-written `/api/*` handlers, called through
  `AgentHttpClient` (`apps/web/src/lib/agent.ts`) from 28 files. Most
  local traffic uses it.
- **Connect-RPC** — one `AgentService` with 48 RPCs
  (`packages/proto/proto/agent.proto`). Only 13 are reached by live
  components (project, apps, variables, users, secrets, processes, Nix
  config, shell status/rebuild, exec, installed packages, module outputs,
  and `PatchNixData`, which is how the Studio saves config edits). The other
  35 duplicate REST endpoints and have no caller.

Keeping both has cost correctness, not just code size. The September 2026
review found the twins drifting apart: the Connect `ReadFile`/`WriteFile`
handlers skip the project-root containment the REST versions enforce; the
Connect handler is mounted without the project guard; search results are
sorted on one side only; a custom `protoc-gen-connect-handlers` plugin
generates entity getters that ignore request fields. The web side carries
71 exported hooks in `use-agent.ts` (37 unused), and demo fixtures exist
twice, once per wire shape.

A separate tRPC API (`packages/api`) serves the cloud features (waitlist,
GitHub, hosted state). tRPC gets its types from the client importing the
server's TypeScript router type, so it cannot serve a Go agent. The
realistic choice for the agent was always REST or Connect.

The Studio is deployed continuously from Cloudflare while each user's agent
is pinned by their flake, so every Studio build talks to agents of many
versions. Wire compatibility has to be checkable, not hoped for.

## Decision

The agent exposes one API: **Connect**, defined in protobuf, organized as
small domain services under a versioned package. REST handlers are retired
as their callers move. tRPC remains the transport for the TypeScript cloud
API only.

**Schema**

- Service definitions are hand-written in `proto/stackpanel/agent/v1/`, one
  file per domain: `AgentService` (`GetAgentInfo` with version and
  capabilities, `Pair`), `ProjectService`, `ConfigService`,
  `SecretService`, `ProcessService`, `ShellService`, `CommandService`,
  `PackageService`, `ModuleService`, `HealthService`, `DeployService`,
  and `EventService`.
- Config types are generated from the proto-nix schemas into
  `proto/stackpanel/config/v1/`. The generator owns the mapping between
  proto field names and kebab-case Nix attribute names, so a `FieldMask`
  path is also a `config.nix` attribute path.
- Messages are typed end to end: no JSON strings or `google.protobuf.Struct`
  payloads. Singleton settings change through `UpdateConfig` with a
  `FieldMask`; keyed collections (apps, variables, users, envs) change
  through per-entry `Upsert`/`Delete` RPCs.
- Side-effect-free reads set `idempotency_level = NO_SIDE_EFFECTS` so
  clients may use HTTP GET.
- `buf lint` and `buf breaking` (against `main`) run in CI, and generated
  code is committed with a `buf generate` drift check, per org ADR-0003.
  Field numbers are never reused.

**Server**

- Cross-cutting concerns live in one interceptor chain applied to every
  service: authentication (`Authorization: Bearer` only; `Pair` is
  exempt), project resolution ([ADR 0005](./0005-per-request-project-selection.md)),
  protovalidate (`connectrpc.com/validate`), panic recovery
  (`connect.WithRecover`), and logging. Handlers contain domain logic only.
- Each domain lives in `internal/agent/<domain>/`, which owns its logic and
  a thin Connect adapter. `internal/agent/server` only composes the mux,
  the interceptors, and the per-project runtime registry.
- Long-running or live work uses server streaming (logs, shell rebuilds,
  commands, deploys, health runs). Browsers support only unary and
  server-streaming calls, so no client or bidirectional streams. The
  browser reaches the agent over plain `http://localhost`, which means
  HTTP/1.1 and roughly six connections per origin, so all live updates are
  multiplexed onto a single `EventService.Watch` stream.
- Failures use Connect error codes with typed details (for example a
  `NixEvalError` with file, line, and message) instead of
  `{success: false}` envelopes.
- `grpcreflect` and `grpchealth` are served so `buf curl` and `grpcurl` can
  discover the API.

**Clients**

- The Studio creates one transport in `AgentProvider`, with interceptors
  that add the auth and project headers, and uses Connect-Query for every
  read and write. The demo mode implements the services in memory with
  `createRouterTransport` and one set of typed fixtures.
- `packages/agent-client` is the published client (generated code plus the
  transport factory) for the Studio, the TUI, scripts, and third parties.
- The Studio calls `GetAgentInfo` on connect and gates features on the
  reported capabilities, showing "update your agent" rather than failing
  on `Unimplemented`.
- The CLI keeps calling the Go domain packages directly, so it works
  without a running agent, and shares that code with the handlers.

## Consequences

**Pros**

- One contract for every client, checked for breaking changes in CI. The
  version skew between the Cloudflare Studio and local agents becomes a
  tooling problem instead of a runtime surprise.
- Cross-cutting behavior (auth, project, validation) cannot be forgotten on
  one route, which is how the REST/Connect twins drifted.
- The web data layer becomes generated code: the hand-written hooks, the
  52 copy-pasted fetch blocks, and the duplicated demo fixtures go away.
- The typed `FieldMask` path removes the hand-written kebab/snake
  conversions that caused saved Studio fields to revert.

**Cons and risks**

- Protobuf's type system is narrower than TypeScript's; sum types need
  `oneof` and optionality needs care.
- The migration touches most Studio screens. It must move one area at a
  time, deleting each REST route when its last caller moves, and never
  keep a REST mirror "for compatibility".
- Contributors need to learn enough `buf` to change the schema safely.

**Follow-ups** (tracked under stackpanel-thq.8)

1. Delete the 35 unused `AgentService` RPCs, the unused `use-agent.ts`
   hooks, and the tRPC `agent` router, which proxies to `localhost:9876`
   from the web server and so cannot reach a user's agent from Cloudflare.
2. Stand up the v1 services, interceptors, and runtime registry beside the
   current server.
3. Move the Studio one area at a time.
4. Delete the old `AgentService`, the REST routes, the SSE and WebSocket
   endpoints, `protoc-gen-connect-handlers` and its committed binary, the
   protobuf-ts output, and the unused JSON-schema output.

## Alternatives considered

- **REST as the single transport.** Carries most traffic today, but has no
  schema, no generated clients, and no breaking-change tooling; the Go and
  TypeScript types would stay hand-maintained on both sides.
- **Adopt the existing `AgentService` as is.** Its shape is the problem: a
  48-method service with generic entity getters/setters and a custom
  handler generator. Migrating callers onto it would carry the drift over.
- **tRPC for the agent.** Not possible: tRPC's types come from a TypeScript
  server router, and the agent is Go. (Org ADR-0003 also rejects
  single-language RPC for services with polyglot consumers.)
- **Serve the Studio from the agent (same origin).** Would remove CORS,
  pairing tokens across origins, browser local-network prompts, and version
  skew, but gives up instant UI updates and the hosted cloud features. Not
  adopted; the capability handshake handles skew instead.

## References

- stackpanel-thq (simplification epic), stackpanel-thq.8 (Agent API v1),
  stackpanel-0h5 (public agent API), stackpanel-382 (demo fixtures from
  proto-nix examples)
- `packages/proto/proto/agent.proto`, `apps/stackpanel-go/internal/agent/server/`,
  `apps/web/src/lib/{agent.ts,use-agent.ts}`, `packages/api/src/routers/agent.ts`
