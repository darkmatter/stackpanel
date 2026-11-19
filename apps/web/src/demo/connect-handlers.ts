import { create } from "@bufbuild/protobuf";
import { MethodOptions_IdempotencyLevel, timestampFromDate } from "@bufbuild/protobuf/wkt";
import { Code, ConnectError, createConnectRouter, type Interceptor } from "@connectrpc/connect";
import { createFetchHandler } from "@connectrpc/connect/protocol";
import { ModuleService } from "@stackpanel/proto/agent/v1/module";
import { ProjectService } from "@stackpanel/proto/agent/v1/project";
import { RebuildShellResponseSchema, ShellService } from "@stackpanel/proto/agent/v1/shell";
import { http } from "msw";
import { DEMO_BASE_URL, demoHealthSummary, demoProject } from "./fixture";
import { createDemoModules } from "./module-service";

const changedFiles = new Set<string>();
let lastBuiltAt = new Date(demoHealthSummary.lastUpdated);
let lastChangeAt = lastBuiltAt;
let rebuilding = false;

const demoModules = createDemoModules((...files) => {
  lastChangeAt = new Date();
  for (const file of files) changedFiles.add(file);
});
export const demoEvaluatedConfig = demoModules.nixConfig;

const selectDemoProject: Interceptor = (next) => (req) => {
  const id = req.header.get("X-Stackpanel-Project");
  if (req.service === ModuleService) {
    // This demo issues no UI grants. Never treat a bound call as a host action.
    if (req.header.has("X-Stackpanel-UI-Grant"))
      throw new ConnectError("No UI grant issued by the demo", Code.PermissionDenied);
    if (id !== null || req.method.idempotency !== MethodOptions_IdempotencyLevel.NO_SIDE_EFFECTS) {
      if (!id?.trim() || id.includes(","))
        throw new ConnectError("Send one nonempty X-Stackpanel-Project", Code.InvalidArgument);
    }
  }
  if (id && id !== demoProject.id)
    throw new ConnectError(`Unknown demo project: ${id}`, Code.NotFound);
  return next(req);
};
const router = createConnectRouter({ grpc: false, grpcWeb: false });
const projectScope = { interceptors: [selectDemoProject] };
router.rpc(ProjectService.method.listProjects, () => ({
  projects: [{ id: demoProject.id, name: demoProject.name, path: demoProject.path, valid: true }],
  defaultProjectId: demoProject.id,
}));
router.service(ModuleService, demoModules.service, projectScope);
router.service(
  ShellService,
  {
    getShellStatus: () => ({
      stale: changedFiles.size > 0,
      changedFiles: [...changedFiles],
      rebuilding,
      lastBuiltAt: timestampFromDate(lastBuiltAt),
      lastNixChangeAt: timestampFromDate(lastChangeAt),
    }),
    async *rebuildShell() {
      if (rebuilding)
        throw new ConnectError("A demo rebuild is already in progress", Code.FailedPrecondition);
      rebuilding = true;
      const building = lastChangeAt;
      try {
        yield create(RebuildShellResponseSchema, { event: { case: "started", value: {} } });
        yield create(RebuildShellResponseSchema, {
          event: {
            case: "outputLine",
            value: "Refreshing the in-memory demo shell (no Nix commands are executed).",
          },
        });
        if (lastChangeAt === building) changedFiles.clear();
        lastBuiltAt = new Date();
        yield create(RebuildShellResponseSchema, {
          event: { case: "completed", value: { exitCode: 0 } },
        });
      } finally {
        rebuilding = false;
      }
    },
  },
  projectScope,
);

export const demoConnectHandlers = router.handlers.flatMap((handler) => {
  const serve = createFetchHandler(handler);
  const path = `${DEMO_BASE_URL}${handler.requestPath}`;
  const post = http.post(path, ({ request }) => serve(request));
  return handler.allowedMethods.includes("GET")
    ? [post, http.get(path, ({ request }) => serve(request))]
    : [post];
});
