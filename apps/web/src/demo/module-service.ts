import { create, toJson, type JsonObject } from "@bufbuild/protobuf";
import { Code, ConnectError, type ServiceImpl } from "@connectrpc/connect";
import {
  ModuleOutputsSchema,
  ModuleSchema,
  ModuleService,
  type ModuleAdoptionAnswer,
  type RegistryModule,
} from "@stackpanel/proto/agent/v1/module";
import {
  demoAppsRpc,
  demoGeneratedFiles,
  demoModuleSeeds,
  demoNixConfig,
  demoPanels,
} from "./fixture";
import {
  demoCatalog,
  demoHealthchecks,
  moduleSeeds,
  makeDemoModule,
  plannedOutputs,
} from "./module-fixtures";

function registryReadme(entry: RegistryModule) {
  return `# ${entry.name}\n\n${entry.description}\n\nInstall the module, then review its outputs before enabling it in the demo project.`;
}

// The agent patches individual Nix attributes. Preserve siblings, replace arrays,
// and never split a literal key (e.g. "browser.name") into path segments.
function patchSettings(base: JsonObject, patch: JsonObject): JsonObject {
  const result = new Map(Object.entries(base));
  for (const [key, value] of Object.entries(patch)) {
    if (!key || ["_type", "_module", "imports"].includes(key) || /\p{Cc}/u.test(key)) {
      throw new ConnectError(`Invalid settings key: ${key}`, Code.InvalidArgument);
    }
    if (value !== null && typeof value === "object" && !Array.isArray(value)) {
      const old = result.get(key);
      const nested = patchSettings(
        old && typeof old === "object" && !Array.isArray(old) ? old : {},
        value,
      );
      if (Object.keys(nested).length) result.set(key, nested);
    } else {
      if (typeof value === "string" && value.includes("\0"))
        throw new ConnectError("Invalid setting value", Code.InvalidArgument);
      result.set(key, value);
    }
  }
  return Object.fromEntries(result);
}

function registryRelease(entry: RegistryModule, version: string, ref: string) {
  const selected = entry.versions.find(
    (release) => release.version === (version || entry.latestVersion),
  );
  if (!selected)
    throw new ConnectError(`Unknown ${entry.slug} version: ${version}`, Code.InvalidArgument);
  if (ref && !/^[A-Za-z0-9][A-Za-z0-9./_+-]*$/.test(ref)) {
    throw new ConnectError("Invalid Git ref", Code.InvalidArgument);
  }
  return { version: selected.version, ref: ref || selected.ref };
}

function enableDiff(current: string[], contributed: string[]) {
  const before = [...new Set(current)].sort();
  const after = [...new Set([...before, ...contributed])].sort();
  return {
    before,
    after,
    added: after.filter((value) => !before.includes(value)),
    removed: [],
    changed: [],
  };
}

export function createDemoModules(onChange: (...files: string[]) => void) {
  const installed = new Map(demoModuleSeeds.map((seed) => [seed.id, makeDemoModule(seed)]));

  function modulesInOrder() {
    return [...installed.values()].sort((a, b) => a.id.localeCompare(b.id));
  }
  let playwrightDecision: boolean | undefined;
  const offer = {
    id: "playwright-config",
    revision: "1",
    type: "bool",
    label: "Manage Playwright configuration",
    module: "playwright",
    description: "Provide playwright.config.ts for browser tests.",
    reason: "Browser tests in the demo project",
  };
  function configDecision(id: string, answers: ModuleAdoptionAnswer[]) {
    if (!answers.length) return playwrightDecision;
    const [choice] = answers;
    if (
      id !== offer.module ||
      answers.length !== 1 ||
      choice?.id !== offer.id ||
      !choice.revision ||
      choice.answer?.kind.case !== "boolValue"
    ) {
      throw new ConnectError("Invalid adoption answer", Code.InvalidArgument);
    }
    if (playwrightDecision !== undefined || choice.revision !== offer.revision)
      throw new ConnectError("Adoption offer is stale; preview again", Code.FailedPrecondition);
    return choice.answer.kind.value;
  }
  const plans = new Map(moduleSeeds.map(({ id }) => [id, plannedOutputs(id)] as const));

  function getModule(id: string) {
    if (!id.trim()) throw new ConnectError("module_id is required", Code.InvalidArgument);
    const mod = installed.get(id);
    if (!mod) throw new ConnectError(`Module ${id} is not installed`, Code.NotFound);
    return mod;
  }

  function getEntry(id: string) {
    if (!id) throw new ConnectError("module_id is required", Code.InvalidArgument);
    const entry = demoCatalog.find((item) => item.id === id || item.slug === id);
    if (!entry) throw new ConnectError(`Unknown registry module: ${id}`, Code.NotFound);
    return entry;
  }

  function projection(entry: RegistryModule) {
    const mod = installed.get(entry.slug);
    const pinned = mod?.source?.flakeInput === entry.slug;
    const matches = pinned
      ? entry.versions.filter((release) => release.ref === mod?.source?.ref)
      : [];
    return {
      ...entry,
      installed: pinned,
      installedVersion: matches.length === 1 ? matches[0]?.version : undefined,
    };
  }

  function toggle(id: string, enabled: boolean, decision = playwrightDecision) {
    const mod = getModule(id);
    const state = enabled ? "enabled" : "disabled";
    if (mod.enabled !== enabled || (id === offer.module && decision !== playwrightDecision)) {
      mod.enabled = enabled;
      if (id === offer.module) playwrightDecision = decision;
      onChange(".stack/config.nix");
    }
    return { message: `${id} ${state} in the demo project` };
  }

  function outputs(id: string, decision = playwrightDecision) {
    const plan = plans.get(id);
    if (!plan) throw new ConnectError(`Missing demo output plan for ${id}`, Code.Internal);
    return id === offer.module && !decision
      ? { ...plan, files: plan.files.filter((file) => file.path !== "playwright.config.ts") }
      : plan;
  }

  function currentOutputs(id: string) {
    return getModule(id).enabled
      ? outputs(id)
      : {
          files: [],
          scripts: [],
          packages: [],
          tasks: [],
          services: [],
          healthchecks: [],
        };
  }

  const service = {
    listModules: () => ({ modules: modulesInOrder() }),
    getModule: ({ moduleId }) => ({ module: getModule(moduleId) }),
    getModuleOutputs({ moduleId }) {
      const out = currentOutputs(moduleId);
      return {
        outputs: create(ModuleOutputsSchema, {
          ...out,
          moduleId,
          services: out.services.map(({ name, proxy }) => ({ name, proxyEnabled: proxy.enable })),
        }),
      };
    },
    enableModule({ moduleId, answers }) {
      const decision = configDecision(moduleId, answers);
      return toggle(moduleId, true, decision);
    },
    disableModule: ({ moduleId }) => toggle(moduleId, false),
    updateModuleConfig({ moduleId, settings }) {
      const mod = getModule(moduleId);
      if (!settings) throw new ConnectError("A settings patch is required", Code.InvalidArgument);
      const updated = patchSettings(mod.settings ?? {}, settings);
      if (JSON.stringify(updated) === JSON.stringify(mod.settings))
        return { message: "Settings unchanged" };
      mod.settings = updated;
      onChange(".stack/config.nix");
      return { message: `Saved ${moduleId} settings in the demo project` };
    },
    previewModuleEnable({ moduleId, answers }) {
      const mod = getModule(moduleId);
      const plan = outputs(mod.id, configDecision(moduleId, answers));
      const current = modulesInOrder()
        .filter((item) => item.enabled)
        .map((item) => outputs(item.id));
      return {
        preview: {
          files: enableDiff(
            [
              ...demoGeneratedFiles.files.filter((file) => !file.module).map((file) => file.path),
              ...current.flatMap((out) => out.files.map((file) => file.path)),
            ],
            plan.files.map((file) => file.path),
          ),
          packages: enableDiff(
            current.flatMap((out) => out.packages.map((pkg) => pkg.name)),
            plan.packages.map((pkg) => pkg.name),
          ),
          services: enableDiff(
            [
              ...Object.keys(demoNixConfig.services).filter((name) => !plans.has(name)),
              ...current.flatMap((out) => out.services.map((svc) => svc.name)),
            ],
            plan.services.map((svc) => svc.name),
          ),
          offers: mod.id === offer.module && playwrightDecision === undefined ? [offer] : [],
        },
      };
    },
    listRegistryModules({ query, category, tag }) {
      const search = query.toLowerCase().trim();
      return {
        modules: demoCatalog
          .filter(
            (entry) =>
              (!category || entry.category.toLowerCase() === category.toLowerCase()) &&
              (!tag || entry.tags.some((value) => value.toLowerCase() === tag.toLowerCase())) &&
              [entry.id, entry.slug, entry.name, entry.description, ...entry.tags].some((s) =>
                s.toLowerCase().includes(search),
              ),
          )
          .map(projection),
      };
    },
    getRegistryModule({ moduleId }) {
      const entry = getEntry(moduleId);
      return { module: projection(entry), readme: registryReadme(entry) };
    },
    installModule({ moduleId: requestedId, version, ref }) {
      const entry = getEntry(requestedId);
      const moduleId = entry.slug;
      if (installed.has(moduleId))
        throw new ConnectError(`${moduleId} is already installed`, Code.AlreadyExists);
      const release = registryRelease(entry, version, ref);
      const seed = moduleSeeds.find(({ id }) => id === moduleId);
      if (!seed) throw new ConnectError(`Missing fixture for ${moduleId}`, Code.Internal);
      const mod = makeDemoModule(seed);
      if (!mod.meta || !mod.source) throw new ConnectError("Incomplete demo module", Code.Internal);
      mod.enabled = false;
      mod.meta.version ??= release.version;
      mod.source.ref = release.ref;
      installed.set(moduleId, mod);
      onChange("flake.nix", "flake.lock");
      return { moduleId, message: `Installed ${moduleId}@${release.version} (not yet enabled)` };
    },
    uninstallModule({ moduleId: requestedId }) {
      const moduleId = getEntry(requestedId).slug;
      getModule(moduleId);
      installed.delete(moduleId);
      if (moduleId === offer.module) playwrightDecision = undefined;
      onChange("flake.nix", "flake.lock", ".stack/config.nix");
      return { message: `Removed ${moduleId} and its demo settings` };
    },
    updateModule({ moduleId, version, ref }) {
      const entry = getEntry(moduleId);
      const mod = getModule(entry.slug);
      if (!mod.meta || !mod.source) throw new ConnectError("Incomplete demo module", Code.Internal);
      const release = registryRelease(entry, version, ref);
      if (mod.source.ref === release.ref) {
        return { message: `${moduleId} is already at ${release.version}` };
      }
      const seed = moduleSeeds.find(({ id }) => id === entry.slug);
      mod.meta.version = seed?.meta?.version ?? release.version;
      mod.source.ref = release.ref;
      onChange("flake.nix", "flake.lock");
      return { message: `Updated ${moduleId} to ${release.version}` };
    },
    async *runModuleAction({ moduleId, actionId, args }) {
      if (!actionId) throw new ConnectError("action_id is required", Code.InvalidArgument);
      const mod = getModule(moduleId);
      if (!mod.enabled) throw new ConnectError(`${moduleId} is disabled`, Code.FailedPrecondition);
      if (actionId !== "inspect" || !mod.actions.inspect)
        throw new ConnectError(`Unknown demo action: ${actionId}`, Code.NotFound);
      if (args && Object.keys(args).length)
        throw new ConnectError("inspect takes no arguments", Code.InvalidArgument);
      yield {
        event: {
          case: "stdout" as const,
          value: `${mod.id}@${mod.meta?.version}\n${JSON.stringify(mod.settings, null, 2)}\n`,
        },
      };
      yield { event: { case: "exitCode" as const, value: 0 } };
    },
  } satisfies Partial<ServiceImpl<typeof ModuleService>>;

  function nixConfig() {
    const modules = modulesInOrder();
    const panelsList = demoPanels
      .filter((panel) => panel.enabled && installed.get(panel.module)?.enabled)
      .sort((a, b) => a.order - b.order || a.id.localeCompare(b.id));
    const modulesListAll = modules.map((mod) => {
      const {
        readmeContent,
        linked: _linked,
        ...fields
      } = toJson(ModuleSchema, mod, {
        alwaysEmitImplicit: true,
      }) as JsonObject;
      return { ...fields, readme: readmeContent };
    });
    const runtimes = ["bun", "go", "rust"].filter((id) => installed.get(id)?.enabled);
    return {
      ...demoNixConfig,
      modulesListAll,
      panelsList,
      moduleOutputs: Object.fromEntries(modules.map(({ id }) => [id, currentOutputs(id)])),
      services: Object.fromEntries(
        Object.entries(demoNixConfig.services).filter(
          ([name]) => !plans.has(name) || installed.get(name)?.enabled,
        ),
      ),
      packages: modules.flatMap(({ id }) => currentOutputs(id).packages),
      healthchecksList: demoHealthchecks.filter((check) => installed.get(check.module)?.enabled),
      appRuntimes: Object.fromEntries(
        runtimes.map((id) => [
          id,
          {
            module: id,
            label: installed.get(id)?.meta?.name,
            icon: installed.get(id)?.meta?.icon,
          },
        ]),
      ),
      appFrameworks: installed.get("tanstack-start")?.enabled
        ? {
            "tanstack-start": {
              label: "TanStack Start",
              module: "tanstack-start",
              icon: "route",
              compatibleRuntimes: ["bun", "node"],
            },
          }
        : {},
      apps: Object.fromEntries(
        Object.entries(demoAppsRpc).map(([id, { name, description, path, type }]) => [
          id,
          {
            ...demoNixConfig.apps[id as keyof typeof demoNixConfig.apps],
            name,
            description,
            path,
            enable: true,
            ...Object.fromEntries(
              runtimes.map((runtime) => [runtime, { enable: runtime === type }]),
            ),
            framework: installed.get("tanstack-start")?.enabled
              ? { "tanstack-start": { enable: id === "web" } }
              : {},
          },
        ]),
      ),
    };
  }
  return { service, nixConfig };
}
