import { describe, expect, it, vi } from "vitest";
import { AgentHttpClient } from "./agent";

describe("agent onboarding responses", () => {
  const client = new AgentHttpClient({ token: "paired-token" });

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
    vi.mocked(fetch).mockResolvedValueOnce(
      Response.json({
        success: true,
        data: { projects, default_path: "/work/my-app" },
      }),
    );
    expect(await client.listProjects()).toEqual({ projects, default_path: "/work/my-app" });
    expect(fetch).toHaveBeenLastCalledWith(expect.stringContaining("/api/project/list"), {
      headers: { "X-Stackpanel-Token": "paired-token" },
    });
  });

  it("unwraps the current project from the agent and accepts the demo's bare shape", async () => {
    const current = {
      has_project: true,
      project: { id: "project", name: "my-app", path: "/work/my-app" },
    };
    vi.mocked(fetch).mockResolvedValueOnce(Response.json({ success: true, data: current }));
    expect(await client.getCurrentProject()).toEqual(current);
    vi.mocked(fetch).mockResolvedValueOnce(Response.json(current));
    expect(await client.getCurrentProject()).toEqual(current);
  });

  it("opens a project and surfaces the agent's reason when it refuses", async () => {
    const project = { id: "project", name: "my-app", path: "/work/my-app" };
    vi.mocked(fetch).mockResolvedValueOnce(
      Response.json({ success: true, data: { success: true, project } }),
    );
    expect((await client.openProject("/work/my-app")).project).toEqual(project);

    vi.mocked(fetch).mockResolvedValueOnce(
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
