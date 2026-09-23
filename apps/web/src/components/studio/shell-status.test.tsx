import type { MessageInitShape } from "@bufbuild/protobuf";
import { Code, ConnectError, createRouterTransport, type ServiceImpl } from "@connectrpc/connect";
import { TransportProvider } from "@connectrpc/connect-query";
import {
  RebuildMethod,
  type RebuildShellResponseSchema,
  ShellService,
} from "@stackpanel/proto/agent/v1/shell";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { ShellStatus } from "./shell-status";

vi.mock("@/lib/agent-provider", () => ({ useAgentContext: () => ({ isConnected: true }) }));
// Live shell events arrive over SSE; these tests drive ShellService alone.
vi.mock("@/lib/use-sse", () => ({
  useShellStatusSSE: () => ({ isStale: false, isRebuilding: false, lastChangedFile: null }),
}));

type RebuildEvent = MessageInitShape<typeof RebuildShellResponseSchema>;

// Serves ShellService in memory, the way the agent's v1 handler answers.
function renderShellStatus(shell: Partial<ServiceImpl<typeof ShellService>>) {
  const transport = createRouterTransport(({ service }) => {
    service(ShellService, shell);
  });
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <TransportProvider transport={transport}>
        <ShellStatus />
      </TransportProvider>
    </QueryClientProvider>,
  );
}

async function rebuildFromStalePopover() {
  fireEvent.click(await screen.findByRole("button", { name: /Shell Stale/ }));
  fireEvent.click(await screen.findByRole("button", { name: /Rebuild Shell/ }));
}

describe("ShellStatus", () => {
  it("shows the stale shell and changed files ShellService reports", async () => {
    renderShellStatus({
      getShellStatus: () => ({ stale: true, changedFiles: ["flake.nix", ".stack/config.nix"] }),
    });

    fireEvent.click(await screen.findByRole("button", { name: /Shell Stale/ }));

    expect(await screen.findByText("flake.nix")).toBeTruthy();
    expect(screen.getByText(".stack/config.nix")).toBeTruthy();
  });

  it("streams the rebuild's output, then shows the refreshed status", async () => {
    let stale = true;
    let finish!: () => void;
    const finished = new Promise<void>((resolve) => {
      finish = resolve;
    });
    const methods: RebuildMethod[] = [];
    renderShellStatus({
      getShellStatus: () => ({ stale }),
      async *rebuildShell(req): AsyncGenerator<RebuildEvent> {
        methods.push(req.method);
        yield { event: { case: "started", value: {} } };
        yield { event: { case: "outputLine", value: "building the devshell" } };
        await finished;
        stale = false;
        yield { event: { case: "completed", value: { exitCode: 0 } } };
      },
    });

    await rebuildFromStalePopover();

    expect(await screen.findByText("building the devshell")).toBeTruthy();
    expect(screen.getByText("Rebuilding...")).toBeTruthy();
    expect(methods).toEqual([RebuildMethod.DEVSHELL]);

    finish();
    expect(await screen.findByText("Shell OK")).toBeTruthy();
  });

  it("shows why a rebuild could not run", async () => {
    renderShellStatus({
      getShellStatus: () => ({ stale: true }),
      async *rebuildShell(): AsyncGenerator<RebuildEvent> {
        yield { event: { case: "started", value: {} } };
        throw new ConnectError("a rebuild is already running", Code.FailedPrecondition);
      },
    });

    await rebuildFromStalePopover();

    // The stale popover the rebuild was started from shows the reason.
    expect(await screen.findByText("a rebuild is already running")).toBeTruthy();
    expect(screen.getByRole("button", { name: /Shell Stale/ })).toBeTruthy();
  });
});
