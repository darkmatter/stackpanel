import { expect, it } from "vite-plus/test";
import type { NixPanel } from "../shared/panel-types";
import {
  compatibleFrameworks,
  getAppPanelMounts,
  getAppProviders,
  planProviderChange,
} from "./app-providers";

const modules = new Map(["js-tools", "native", "web-tools", "portable"].map((id) => [id, {}]));
const config = {
  apps: {
    web: { type: "native", js: { enable: true }, framework: { site: { enable: true } } },
    api: { native: { enable: true } },
    script: {},
  },
  appRuntimes: { js: { module: "js-tools" }, native: { module: "native" }, disabled: { module: "disabled" } },
  appFrameworks: {
    site: { module: "web-tools", label: "Site", compatibleRuntimes: ["js"] },
    "native.web": { module: "native", compatibleRuntimes: ["native"] },
    portable: { module: "portable", compatibleRuntimes: [] },
  },
};

function providersFor(appId: string) {
  const providers = getAppProviders(config, appId, modules);
  if (!providers) throw new Error(`Missing app ${appId}`);
  return providers;
}

it("reads enabled owners and per-app flags, not legacy app type or another app's choices", () => {
  const web = providersFor("web");
  expect(web.runtime.map(({ id, enabled }) => [id, enabled])).toEqual([
    ["js", true],
    ["native", false],
  ]);
  expect(compatibleFrameworks(web).map((p) => p.id)).toEqual(["site", "portable"]);
  expect(compatibleFrameworks(providersFor("api")).map((p) => p.id)).toEqual([
    "native.web",
    "portable",
  ]);
  expect(compatibleFrameworks(providersFor("script"))).toHaveLength(3);
  expect(getAppProviders(config, "missing", modules)).toBeNull();
});

it("does not infer an owner or grant unrestricted compatibility from incomplete metadata", () => {
  expect(getAppProviders({ ...config, appRuntimes: { native: {} } }, "web", modules)).toBeNull();
  expect(getAppProviders({ ...config, appFrameworks: { site: { module: "web-tools" } } }, "web", modules)).toBeNull();
});

it("switches only canonical enable flags, clearing conflicts before enabling their replacement", () => {
  const web = providersFor("web");
  expect(planProviderChange(web, "runtime", "native")).toEqual([
    { path: "framework.site.enable", enabled: false },
    { path: "js.enable", enabled: false },
    { path: "native.enable", enabled: true },
  ]);
  expect(planProviderChange(web, "framework", "portable")).toEqual([
    { path: "framework.site.enable", enabled: false },
    { path: "framework.portable.enable", enabled: true },
  ]);
  expect(planProviderChange(web, "framework", null)).toEqual([
    { path: "framework.site.enable", enabled: false },
  ]);
  expect(() => planProviderChange(web, "framework", "native.web")).toThrow("Unavailable framework");
  expect(planProviderChange(providersFor("api"), "framework", "native.web")).toEqual([
    { path: "framework.native\\.web.enable", enabled: true },
  ]);
});

function panel(module: string, id: string, slot: string, props?: Partial<NixPanel>): NixPanel {
  return {
    module,
    id,
    title: id,
    slot,
    order: 0,
    enabled: true,
    fields: [],
    type: "PANEL_TYPE_APP_CONFIG",
    apps: { web: { enabled: true, config: {} } },
    ...props,
  };
}

it("mounts selected owners' cards and distinct eligible app tabs exactly once", () => {
  const js = panel("js-tools", "settings", "app:runtime");
  const site = panel("web-tools", "settings", "app:framework");
  const image = panel("image-tools", "build", "app:container");
  const deploy = panel("cloud-tools", "build", "app:deployment");
  const lint = panel("quality", "lint", "app:tab", { type: "PANEL_TYPE_STATUS", apps: {} });
  const group = panel("quality", "checks", "app:tab", { type: "PANEL_TYPE_TABS", tabs: ["lint"] });
  const panels = [
    js,
    site,
    image,
    deploy,
    lint,
    lint,
    group,
    panel("native", "options", "app:runtime"),
    panel("portable", "options", "app:framework"),
    panel("web-tools", "global", "module"),
    panel("quality", "disabled", "app:tab", { apps: { web: { enabled: false, config: {} } } }),
    panel("quality", "no-app-data", "app:tab", { apps: {} }),
  ];
  expect(getAppPanelMounts(panels, "web", providersFor("web"))).toEqual({
    runtime: [js],
    framework: [site],
    tabs: [image, deploy, group],
  });
  expect(getAppPanelMounts(panels, "api", providersFor("api"))).toEqual({
    runtime: [],
    framework: [],
    tabs: [lint],
  });
});
