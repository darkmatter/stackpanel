/// <reference types="vite-plus/test/globals" />
import { EventEmitter, once } from "node:events";
import { fromJson, type MessageInitShape } from "@bufbuild/protobuf";
import { ValueSchema } from "@bufbuild/protobuf/wkt";
import {
  Code,
  ConnectError,
  createClient,
  createRouterTransport,
  type ServiceImpl,
} from "@connectrpc/connect";
import {
  ModuleService,
  type RunModuleActionResponseSchema,
} from "@stackpanel/proto/agent/v1/module";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { StrictMode, useState } from "react";
import * as agentProvider from "@/lib/agent-provider";
import { agentQueryKeys } from "@/lib/use-agent";
import {
  ModuleActionRunnerDialog,
  type ModuleActionRunnerDialogProps,
  useModuleActionRunner,
} from "./command-runner";

type ActionEvent = MessageInitShape<typeof RunModuleActionResponseSchema>;
const scope = ["agent", "modules", "localhost", 9876, "first-project", "t0", true] as const;
const request = {
  moduleId: "deploy",
  actionId: "inspect",
  args: { app: "web app", verbose: true },
};

const pairedIdentity = {
  selectedProjectId: "first-project",
  token: "test-token",
  isAuthenticated: true,
};
let identity: { selectedProjectId: string | null; token: string | null; isAuthenticated: boolean };
vi.mock("@/lib/agent-provider", async (importOriginal) => ({
  ...(await importOriginal<typeof agentProvider>()),
  useAgentContext: () => identity,
}));
vi.mock("./panels/modules/use-modules", () => ({ useModuleQueryScope: () => scope }));

function SubmitAction({ onSuccess }: Pick<ModuleActionRunnerDialogProps, "onSuccess">) {
  const { start } = useModuleActionRunner();
  const [run, setRun] = useState<ModuleActionRunnerDialogProps | null>(null);
  function submit() {
    setRun(
      start({
        ...request,
        label: "Inspect app",
        invalidates: ["apps"],
        onClose: () => setRun(null),
        onSuccess,
      }),
    );
  }
  return (
    <>
      <button type="button" onClick={submit}>
        Submit
      </button>
      {run && <ModuleActionRunnerDialog {...run} />}
    </>
  );
}

function setup(
  runModuleAction: ServiceImpl<typeof ModuleService>["runModuleAction"],
  unavailable?: "project" | "credential",
) {
  identity = { ...pairedIdentity };
  if (unavailable === "project") identity.selectedProjectId = null;
  if (unavailable === "credential") {
    identity.token = null;
    identity.isAuthenticated = false;
  }
  const transport = createRouterTransport((router) =>
    router.service(ModuleService, { runModuleAction }),
  );
  vi.spyOn(agentProvider, "useModuleServiceClient").mockReturnValue(
    createClient(ModuleService, transport),
  );
  const cache = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const onSuccess = vi.fn();
  render(
    <StrictMode>
      <QueryClientProvider client={cache}>
        <SubmitAction onSuccess={onSuccess} />
      </QueryClientProvider>
    </StrictMode>,
  );
  return {
    cache,
    onSuccess,
    submit: () => fireEvent.click(screen.getByRole("button", { name: "Submit" })),
  };
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("submitted module actions", () => {
  it.each(["project", "credential"] as const)(
    "never starts a module process without a %s",
    async (missing) => {
      const requests: string[] = [];
      const { submit } = setup(async function* (request): AsyncGenerator<ActionEvent> {
        requests.push(request.actionId);
        yield { event: { case: "exitCode", value: 0 } };
      }, missing);
      submit();
      expect(await screen.findByRole("alert")).toBeTruthy();
      expect(requests).toEqual([]);
    },
  );

  it("streams ordered, labeled output before exit; delivers JSON and refreshes this project's data once", async () => {
    const action = new EventEmitter();
    const gate = once(action, "finish");
    const requests: unknown[] = [];
    const result = { rows: [{ healthy: true }] };
    const { cache, onSuccess, submit } = setup(async function* (req): AsyncGenerator<ActionEvent> {
      requests.push(req);
      yield { event: { case: "stdout", value: "Inspecting app" } };
      yield { event: { case: "stderr", value: "Version mismatch" } };
      yield { event: { case: "json", value: fromJson(ValueSchema, result) } };
      await gate;
      yield { event: { case: "exitCode", value: 0 } };
    });
    const refreshed = [
      [...scope, "catalog"],
      agentQueryKeys.nixConfig(),
      agentQueryKeys.apps(),
    ];
    const unrelated = [
      "agent",
      "modules",
      "localhost",
      9876,
      "other-project",
      "t1",
      true,
      "catalog",
    ];
    for (const key of [...refreshed, unrelated]) cache.setQueryData(key, true);

    expect(requests).toHaveLength(0);
    submit();
    const dialog = within(await screen.findByRole("dialog", { name: "Inspect app" }));
    const output = dialog.getByRole("log", { name: "Action output" });
    try {
      await within(output).findByText(/"healthy": true/);
      expect(output.textContent).toMatch(/stdoutInspecting appstderrVersion mismatchjson/);
      expect(dialog.getByRole("status").textContent).toBe("Running");
      expect(onSuccess).not.toHaveBeenCalled();
      expect(cache.getQueryState(agentQueryKeys.apps())?.isInvalidated).toBe(false);
    } finally {
      action.emit("finish");
    }
    await dialog.findByText("Exit code 0");
    await waitFor(() => expect(onSuccess.mock.calls).toEqual([[result]]));
    expect(requests).toEqual([expect.objectContaining(request)]);
    for (const key of refreshed) expect(cache.getQueryState(key)?.isInvalidated).toBe(true);
    expect(cache.getQueryState(unrelated)?.isInvalidated).toBe(false);
  });

  it("cancels the RPC when the user closes a running action", async () => {
    const action = new EventEmitter();
    const gate = once(action, "finish");
    let signal: AbortSignal | undefined;
    const { submit, onSuccess } = setup(
      async function* (_request, context): AsyncGenerator<ActionEvent> {
        signal = context.signal;
        yield { event: { case: "stdout", value: "Waiting for app" } };
        await gate;
        yield { event: { case: "exitCode", value: 0 } };
      },
    );
    submit();
    try {
      await screen.findByText("Waiting for app");
      fireEvent.click(screen.getByRole("button", { name: "Close" }));
      await waitFor(() => expect(signal?.aborted).toBe(true));
      expect(screen.queryByRole("dialog")).toBeNull();
      expect(onSuccess).not.toHaveBeenCalled();
    } finally {
      action.emit("finish");
    }
  });

  it("keeps the transcript and the process exit code when an action fails", async () => {
    const { submit, onSuccess } = setup(async function* (): AsyncGenerator<ActionEvent> {
      yield { event: { case: "stderr", value: "No deployment selected" } };
      yield { event: { case: "exitCode", value: 17 } };
    });
    submit();
    await screen.findByText("Exit code 17");
    expect(screen.getByRole("log").textContent).toContain("No deployment selected");
    expect(onSuccess).not.toHaveBeenCalled();
  });

  it.each([
    ["truncated", "ended without an exit code"],
    ["disconnected", "connection lost"],
  ])("does not report success on a %s stream", async (kind, reason) => {
    const { submit, onSuccess } = setup(async function* (): AsyncGenerator<ActionEvent> {
      yield { event: { case: "stdout", value: "Started" } };
      if (kind === "disconnected") {
        yield { event: { case: "exitCode", value: 0 } };
        throw new ConnectError("connection lost", Code.Unavailable);
      }
    });
    submit();
    expect((await screen.findByRole("alert")).textContent).toContain(reason);
    expect(screen.getByRole("log").textContent).toContain("Started");
    expect(onSuccess).not.toHaveBeenCalled();
  });
});
