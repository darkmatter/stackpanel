// @vitest-environment jsdom
import { afterEach, expect, test } from "vite-plus/test";
import type { ActionResult } from "./bridge.js";
import { registerPanelElements, type PanelElementRun } from "./elements.js";

registerPanelElements();
afterEach(() => document.body.replaceChildren());

// The runner deliberately ignores abort: a slow provider can still settle after revocation.
function mountView() {
  const view = document.createElement("sp-status-view");
  const calls: {
    args: Parameters<PanelElementRun>[1];
    signal: AbortSignal;
    reason: Parameters<PanelElementRun>[3];
    resolve: (result: ActionResult) => void;
  }[] = [];
  view.run = (_action, args, signal, reason) => {
    const { promise, resolve } = Promise.withResolvers<ActionResult>();
    calls.push({ args, signal, reason, resolve });
    return promise;
  };
  document.body.append(view);
  const root = view.shadowRoot!;
  const [load, updates] = Array.from(root.querySelectorAll("button"));
  return {
    view,
    calls,
    load: load!,
    updates: updates!,
    output: root.querySelector("pre")!,
    updated: root.querySelector("time")!,
  };
}

test("Load once requires a target and never follows a selection; late results cannot reappear", async () => {
  const { view, calls, load, updates, output, updated } = mountView();
  load.click(); // No action yet.
  view.args = { app: "" };
  view.action = "status";
  load.click(); // The selected-app prop is present, but empty.
  updates.click();
  expect(calls).toHaveLength(0);

  view.args = { app: "frontend" };
  load.click();
  expect(calls[0]).toMatchObject({ reason: "load-once", args: { app: "frontend" } });
  view.args = { app: "backend" };
  expect(calls[0]!.signal.aborted).toBe(true);
  calls[0]!.resolve({ stdout: "obsolete", stderr: "", exitCode: 0 });
  await Promise.resolve();
  expect(calls).toHaveLength(1);
  expect(output.textContent).toBe("");
  expect(updated.hidden).toBe(true);

  load.click();
  calls[1]!.resolve({
    stdout: "<em>running</em>",
    stderr: "warning",
    json: { ready: true },
    exitCode: 0,
  });
  await Promise.resolve();
  expect(output.textContent).toContain("<em>running</em>");
  expect(output.querySelector("em")).toBeNull();
  expect(output.textContent).toContain("warning");
  expect(output.textContent).toContain('"ready": true');
  expect(updated.dateTime).not.toBe("");
  view.args = { app: "frontend" };
  expect(calls).toHaveLength(2);
  expect(output.textContent).toBe("");
  expect(updated.hidden).toBe(true);

  load.click();
  calls[2]!.resolve({ stdout: "", stderr: "permission denied", exitCode: 1 });
  await Promise.resolve();
  expect(output.textContent).toContain("permission denied");
  expect(view.shadowRoot!.querySelector('[role="status"]')?.textContent).toContain(
    "exited with code 1",
  );
  expect(updated.hidden).toBe(true);
});

test("automatic updates are scoped to a successful opt-in, a mounted element and its current selection", async () => {
  const { view, calls, updates, output, updated } = mountView();
  const ok = { stdout: "ready", stderr: "", exitCode: 0 };
  view.action = "status";
  view.args = { app: "one" };
  expect(calls).toHaveLength(0);
  updates.click();
  view.args = { app: "two" }; // No follow-up while first approval is still pending.
  expect(calls[0]!.signal.aborted).toBe(true);
  calls[0]!.resolve(ok);
  await Promise.resolve();
  expect(calls).toHaveLength(1);

  updates.click();
  expect(calls[1]!.reason).toBe("allow-automatic");
  calls[1]!.resolve(ok);
  await Promise.resolve();
  view.args = { app: "two" }; // A host rerender is not a selection change.
  expect(calls).toHaveLength(2);
  view.args = { app: "three" };
  expect(calls[2]).toMatchObject({ reason: "selection-change", args: { app: "three" } });
  expect(updates.textContent).toBe("Stop updates");
  updates.click();
  expect(calls[2]!.signal.aborted).toBe(true);
  view.args = { app: "four" };
  expect(calls).toHaveLength(3);

  updates.click();
  view.remove();
  expect(calls[3]!.signal.aborted).toBe(true);
  document.body.append(view);
  calls[2]!.resolve(ok);
  calls[3]!.resolve(ok);
  await Promise.resolve();
  view.args = { app: "five" };
  expect(calls).toHaveLength(4);
  expect(output.textContent).toBe("");
  expect(updated.dateTime).toBe("");
});
