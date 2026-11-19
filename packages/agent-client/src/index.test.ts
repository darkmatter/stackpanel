import { expect, it, vi } from "vite-plus/test";
import { createAgentClient, createModuleServiceClient } from "./index";

it("authenticates AgentService with a bearer credential", async () => {
  const fetch = vi.spyOn(globalThis, "fetch").mockResolvedValue(Response.json({}));
  try {
    await createAgentClient({ token: "paired-token" }).getProject({});
    const [url, init] = fetch.mock.calls[0]!;
    expect(url).toBe("http://localhost:9876/stackpanel.agent.AgentService/GetProject");
    const headers = new Headers(init?.headers);
    expect(headers.get("Authorization")).toBe("Bearer paired-token");
    expect(headers.has("X-Stackpanel-Token")).toBe(false);
  } finally {
    fetch.mockRestore();
  }
});

it("calls the module service with the configured endpoint, credential and project", async () => {
  const fetch = vi
    .spyOn(globalThis, "fetch")
    .mockImplementation(async () => Response.json({ modules: [{ id: "example" }] }));
  try {
    const client = createModuleServiceClient({
      host: "agent.example.test",
      port: 8123,
      token: "paired-token",
      projectId: "shop",
    });
    const response = await client.listModules({});
    expect(response.modules.map((module) => module.id)).toEqual(["example"]);
    const [url, init] = fetch.mock.calls[0]!;
    expect(url).toBe(
      "http://agent.example.test:8123/stackpanel.agent.v1.ModuleService/ListModules",
    );
    const headers = new Headers(init?.headers);
    expect(headers.get("Authorization")).toBe("Bearer paired-token");
    expect(headers.get("X-Stackpanel-Project")).toBe("shop");
  } finally {
    fetch.mockRestore();
  }
});
