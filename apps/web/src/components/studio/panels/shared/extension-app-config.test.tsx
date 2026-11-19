import { useAppModuleConfig, useModuleConfig } from "@stackpanel/extension-sdk/react";
import { renderHook, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vite-plus/test";

const bridge = vi.hoisted(() => ({
  getContext: vi.fn(),
  getConfig: vi.fn(),
  patchModuleConfig: vi.fn(),
  onConfigChange: vi.fn(() => () => {}),
}));
vi.mock("@stackpanel/extension-sdk", () => bridge);

describe.each([
  { mount: "module", scope: {}, useConfig: useModuleConfig },
  { mount: "app", scope: { appId: "shop" }, useConfig: useAppModuleConfig },
])("$mount config", ({ scope, useConfig }) => {
  it("offers only a relative writer with a patch-only grant", async () => {
    bridge.getContext.mockResolvedValue({ ...scope, permissions: ["config:patch"] });
    const { result } = renderHook(() => useConfig());
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current).toMatchObject({ ...scope, settings: null, error: null });
    expect(bridge.getConfig).not.toHaveBeenCalled();
    expect(bridge.onConfigChange).not.toHaveBeenCalled();
    await result.current.patchModuleConfig?.({ workers: 4 });
    expect(bridge.patchModuleConfig.mock.calls).toEqual([[{ workers: 4 }]]);
  });

  it("reads settings without offering a writer with a read-only grant", async () => {
    bridge.getContext.mockResolvedValue({ ...scope, permissions: ["config:read"] });
    bridge.getConfig.mockResolvedValue({ workers: 2 });
    const { result } = renderHook(() => useConfig());
    await waitFor(() => expect(result.current.settings).toEqual({ workers: 2 }));
    expect(result.current.patchModuleConfig).toBeUndefined();
  });
});
