import { describe, expect, it, vi } from "vitest";
import { AgentHttpClient } from "./agent";

describe("agent onboarding responses", () => {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const token = `${encode({ alg: "HS256", typ: "JWT" })}.${encode({ agent_id: "local-agent", exp: Math.floor(Date.now() / 1000) + 3600 })}.signature`;
  const client = new AgentHttpClient({ token, requireAuth: true });

  function mockProtectedResponse(response: Response) {
    vi.mocked(fetch)
      .mockResolvedValueOnce(Response.json({ status: "ok", agent_id: "local-agent" }))
      .mockResolvedValueOnce(response);
  }

  it("reads repository identity from the Go health response", async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      Response.json({
        status: "ok",
        project_root: "/work/my-app",
        has_project: true,
        agent_id: "local-agent",
      }),
    );
    expect(await client.health()).toMatchObject({
      projectRoot: "/work/my-app",
      hasProject: true,
      agentId: "local-agent",
    });
  });

  it("does not treat a failed health response as a connected agent", async () => {
    vi.mocked(fetch).mockResolvedValueOnce(Response.json({ status: "ok" }, { status: 503 }));
    expect(await client.ping()).toBeNull();
  });

  it("unwraps registered repositories returned by the authenticated project endpoint", async () => {
    const projects = [{ id: "project", name: "my-app", path: "/work/my-app" }];
    mockProtectedResponse(
      Response.json({
        success: true,
        data: { projects, default_path: "/work/my-app" },
      }),
    );
    expect(await client.listProjects()).toEqual({ projects, default_path: "/work/my-app" });
    const [probe, request] = vi.mocked(fetch).mock.calls.slice(-2);
    expect(probe[0]).toBe("http://localhost:9876/health");
    expect(probe[1]).toMatchObject({ redirect: "error", credentials: "omit" });
    expect(new Headers(probe[1]?.headers).has("X-Stackpanel-Token")).toBe(false);
    expect(request[0]).toBe("http://localhost:9876/api/project/list");
    expect(request[1]).toMatchObject({
      redirect: "error",
      credentials: "omit",
      headers: { "X-Stackpanel-Token": token },
    });
  });

  it("unwraps the current project from the agent and accepts the demo's bare shape", async () => {
    const current = {
      has_project: true,
      project: { id: "project", name: "my-app", path: "/work/my-app" },
    };
    mockProtectedResponse(Response.json({ success: true, data: current }));
    expect(await client.getCurrentProject()).toEqual(current);
    mockProtectedResponse(Response.json(current));
    expect(await client.getCurrentProject()).toEqual(current);
  });

  it("opens a project and surfaces the agent's reason when it refuses", async () => {
    const project = { id: "project", name: "my-app", path: "/work/my-app" };
    mockProtectedResponse(Response.json({ success: true, data: { success: true, project } }));
    expect((await client.openProject("/work/my-app")).project).toEqual(project);

    mockProtectedResponse(
      Response.json(
        {
          success: true,
          data: {
            valid: false,
            error: "not_git_repo",
            message: "Directory is not a git repository",
          },
        },
        { status: 400 },
      ),
    );
    await expect(client.openProject("/work/plain-dir")).rejects.toThrow(
      "Directory is not a git repository",
    );
  });
});
