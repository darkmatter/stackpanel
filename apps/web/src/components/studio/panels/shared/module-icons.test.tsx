import { render, waitFor } from "@testing-library/react";
import { ArrowDownAZ, Boxes } from "lucide-react";
import { expect, it } from "vite-plus/test";
import { getModuleIconByName } from "./module-icons";

it("renders a Lucide icon outside the built-in module set by kebab or Pascal name", async () => {
  const Icon = getModuleIconByName("arrow-down-a-z");
  expect(getModuleIconByName("ArrowDownAZ")).toBe(Icon);
  const { container } = render(
    <>
      <Icon size={18} />
      <ArrowDownAZ size={18} />
    </>,
  );
  await waitFor(() => {
    const [resolved, reference] = container.querySelectorAll("svg");
    expect(resolved?.innerHTML).toBe(reference.innerHTML);
  });
});

it("falls back for missing, unknown and inherited names", () => {
  for (const name of [undefined, "not-a-lucide-icon", "__proto__", "constructor"]) {
    expect(getModuleIconByName(name)).toBe(Boxes);
  }
});
