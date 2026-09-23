# 0005 — Agent requests select their project per request

- **Status**: Accepted
- **Date**: 2026-09-23
- **Related**: [ADR 0004](./0004-agent-api-on-connect.md)

## Context

One agent process serves every client on the machine: Studio tabs, the TUI,
scripts, and (with the planned global service, stackpanel-f1n) the whole
user session. Today it holds a single project:

- `s.config.ProjectRoot` is chosen at startup (flag or env, then the working
  directory, then the saved "current project" in
  `~/.config/stackpanel/stackpanel.yaml`).
- `/api/project/open` overwrites that field (`project_handlers.go:173`)
  with no lock while roughly 99 other sites read it, then
  `reinitializeExecutor()` (`server.go:559`) swaps the singletons: executor,
  data store, shell manager, and flake watcher.
- Every client therefore shares one current project. Two Studio tabs, or
  the Studio and the CLI, on different projects switch each other.

A per-request design has existed since the initial import (2026-01-19):
`project_context.go` resolves the project from an `X-Stackpanel-Project`
header, then a query parameter, then the default and current projects. It
was never mounted on a route. The surrounding code assumed it worked: the
web app sends the header, CORS allows it, and `stack project` help and the
docs tell users to send it.

stackpanel-7hn asked for exactly this ("support multiple projects at once
... by passing the project in every request"). The stackpanel-f1n spec
(`docs/superpowers/specs/2026-06-15-global-agent-service.md`) instead kept
a single current project with open/switch endpoints and listed replacing
them as a non-goal. The two plans conflicted.

## Decision

Each agent request names its project. The agent keeps no global
"current project".

- A Connect interceptor ([ADR 0004](./0004-agent-api-on-connect.md))
  resolves the project from the `Stackpanel-Project` request header. When
  the header is absent it falls back to the registry's default project and
  then its current project, so interactive CLI use stays convenient.
- The interceptor attaches that project's **runtime** to the request
  context. A runtime owns everything project-scoped: the command executor,
  the data store, the shell manager, the flake watcher, caches, and an
  `os.Root` opened on the project directory. File access goes through that
  root, so escaping the project is impossible by construction.
- Runtimes live in a registry keyed by project ID. They start on first use
  and are shut down after an idle period.
- Handlers read the runtime from the context; nothing reads a global
  project field.
- Event streams are scoped to a project.
- The project registry in `~/.config/stackpanel/stackpanel.yaml` stays the
  source of known projects. "Open" becomes "register or select", not
  "replace the agent's global state".

This supersedes the single-current-project model in the stackpanel-f1n
spec; that spec's non-goal is updated accordingly.

## Consequences

**Pros**

- Clients stop interfering with each other; one global agent can serve
  several projects at once, which the global service needs.
- The data race on `s.config.ProjectRoot` and the goroutine started on every
  project switch disappear with the mutable field.
- Path containment is structural (`os.Root`) instead of a helper each file
  handler has to remember.

**Cons and risks**

- Memory grows with the number of active projects; idle eviction must be
  tuned.
- Caches keyed by project must not leak across runtimes (today a
  process-wide config cache survives project switches).

**Follow-ups** (tracked under stackpanel-thq.8.1)

- Until the interceptor lands, delete `project_context.go` and correct the
  CLI help and docs that advertise a header the agent ignores. The
  resolution logic is small enough to rewrite as the interceptor.

## Alternatives considered

- **Keep one current project with open/switch (f1n spec as written).**
  Simple, but a global agent shared by several clients makes interference
  the normal case, and the switch path is racy.
- **Mount the existing `project_context.go` middleware.** It only resolves
  a path; every handler still uses per-agent singletons bound to one
  project, so it would not deliver multi-project behavior.
- **One agent process per project.** Rejected by stackpanel-f1n: it
  multiplies services, ports, and pairing state.

## References

- stackpanel-thq.8.1, stackpanel-7hn, stackpanel-f1n
- `apps/stackpanel-go/internal/agent/server/{project_context.go,project_handlers.go,server.go}`
- `apps/stackpanel-go/cmd/cli/project.go`, `apps/docs/content/docs/cli/project/`
