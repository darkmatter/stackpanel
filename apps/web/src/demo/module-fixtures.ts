import { create } from "@bufbuild/protobuf";
import { ModuleSchema, RegistryModuleSchema } from "@stackpanel/proto/agent/v1/module";
import {
  demoGeneratedFiles,
  demoHealthSummary,
  demoModuleSeeds,
  demoNixConfig,
  demoPanels,
  type DemoModuleSeed,
} from "./fixture";

const inspect = {
  label: "Inspect demo configuration",
  outputMode: "stream",
  argsSchema: { type: "object", properties: {}, additionalProperties: false },
};

// These two local releases exercise version selection without fetching a registry.
const available: DemoModuleSeed[] = [
  {
    id: "playwright",
    meta: {
      name: "Playwright",
      description: "Browser testing with a managed Playwright configuration.",
      category: "testing",
      icon: "theater",
      homepage: "https://playwright.dev",
    },
    source: { type: "registry", registryId: "playwright", flakeInput: "playwright" },
    tags: ["testing", "browser"],
    features: { files: true, packages: true, tasks: true },
    settings: { browser: "chromium" },
    configSchema: JSON.stringify({
      type: "object",
      properties: {
        browser: { type: "string", enum: ["chromium", "firefox", "webkit"] },
        runner: {
          type: "object",
          properties: { workers: { type: "integer" }, retries: { type: "integer" } },
        },
        "demo.key": { type: "string" },
      },
    }),
    actions: { inspect },
  },
  {
    id: "rust",
    meta: {
      name: "Rust",
      description: "Rust toolchain and Cargo for local development.",
      category: "language",
      icon: "code",
      homepage: "https://www.rust-lang.org",
    },
    source: { type: "registry", registryId: "rust", flakeInput: "rust" },
    tags: ["cargo", "runtime"],
    features: { packages: true },
    actions: { inspect },
  },
];

export const moduleSeeds = [...demoModuleSeeds, ...available];

export function makeDemoModule(seed: DemoModuleSeed) {
  return create(ModuleSchema, {
    enablePath: `modules.${seed.id}.enable`,
    configPath: `modules.${seed.id}.settings`,
    settings: {},
    readmeContent: `# ${seed.meta?.name ?? seed.id}\n\n${seed.meta?.description ?? ""}`,
    ...seed,
  });
}

// An installed module's metadata version need not match a catalog release name.
// Preinstalled external inputs are pinned to main; local demo releases use tags.
export const demoCatalog = moduleSeeds.flatMap((seed) => {
  const slug = seed.source?.flakeInput;
  if (!slug) return [];
  const releases = seed.source?.ref ? [seed.source.ref] : ["1.1.0", "1.0.0"];
  return [
    create(RegistryModuleSchema, {
      name: seed.meta?.name,
      description: seed.meta?.description,
      category: seed.meta?.category,
      icon: seed.meta?.icon,
      homepage: seed.meta?.homepage,
      id: seed.source?.registryId ?? slug,
      slug,
      author: seed.meta?.author ?? "Stackpanel",
      tier: "official",
      tags: seed.tags,
      features: Object.entries(seed.features ?? {})
        .filter(([, enabled]) => enabled === true)
        .map(([key]) => key),
      uiSlots: [
        ...new Set(
          demoPanels.filter((panel) => panel.module === seed.id).map((panel) => panel.slot),
        ),
      ],
      latestVersion: releases[0],
      versions: releases.map((version) => ({
        version,
        ref: seed.source?.ref ?? `v${version}`,
        followsNixpkgs: true,
        flakeUrl: `github:darkmatter/stackpanel-registry?dir=modules/${slug}`,
        flakePath: "stackpanelModules.default",
      })),
    }),
  ];
});

export const demoHealthchecks = Object.values(demoHealthSummary.modules).flatMap((group) =>
  group.checks.map(({ check }) => check),
);

// Shared by the evaluated snapshot, GetModuleOutputs and enable previews.
export function plannedOutputs(moduleId: string) {
  const files = demoGeneratedFiles.files.filter((file) => file.module === moduleId);
  const packages = demoNixConfig.packages.filter((pkg) => pkg.module === moduleId);
  const services = Object.entries(demoNixConfig.services).filter(([name]) => name === moduleId);
  return {
    files:
      moduleId === "playwright"
        ? [{ module: moduleId, path: "playwright.config.ts", type: "text" }]
        : files.map(({ path, description }) => ({
            module: moduleId,
            path,
            description,
            type: "json",
          })),
    packages: [
      ...packages,
      ...(moduleId === "playwright"
        ? ["playwright"]
        : moduleId === "rust"
          ? ["cargo", "rustc"]
          : []
      ).map((name) => ({
        module: moduleId,
        name,
        attrPath: name,
        version: "",
        source: "devshell",
      })),
    ],
    services: services.map(([name, service]) => ({
      module: moduleId,
      name,
      port: service.port,
      proxy: { enable: false },
    })),
    healthchecks: demoHealthchecks.filter((check) => check.module === moduleId),
    tasks: moduleId === "playwright" ? [{ module: moduleId, name: "e2e" }] : [],
    scripts: [],
  };
}
