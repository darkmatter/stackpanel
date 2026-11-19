// Browser entry point; the test bundles this exactly as an external panel author would.
import { getConfig, getContext, patchModuleConfig, proxyFetch } from "@stackpanel/extension-sdk";
import { registerPanelElements } from "@stackpanel/extension-sdk/elements";

async function renderStatus() {
  registerPanelElements();
  const context = await getContext();
  const status = document.createElement("p");
  const metric = document.createElement("sp-metric");
  metric.setAttribute("label", "Module");
  metric.setAttribute("value", context.moduleId);
  document.body.append(metric);
  const read = document.createElement("button");
  read.textContent = "Read greeting";
  read.onclick = async () => {
    try {
      const config = await getConfig();
      if (typeof config.greeting !== "string") throw new Error("Greeting is not configured.");
      status.textContent = `${context.moduleId}/${context.panelId}: ${config.greeting}`;
    } catch (error) {
      status.textContent = error instanceof Error ? error.message : String(error);
    }
  };
  document.body.append(read, status);
  const save = document.createElement("button");
  save.textContent = "Try changing greeting";
  save.onclick = async () => {
    try {
      await patchModuleConfig({ greeting: "changed by panel" });
      status.textContent = "Settings changed";
    } catch (error) {
      status.textContent = error instanceof Error ? error.message : String(error);
    }
  };
  document.body.append(save);
  const service = document.createElement("button");
  service.textContent = "Read local service";
  service.onclick = async () => {
    try {
      status.textContent = (await proxyFetch("health", "/status")).body;
    } catch (error) {
      status.textContent = error instanceof Error ? error.message : String(error);
    }
  };
  document.body.append(service);
}

void renderStatus().catch((error: unknown) => {
  document.body.textContent = String(error);
});
