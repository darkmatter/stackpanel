import { render, screen } from "@testing-library/react";
import { expect, it } from "vite-plus/test";
import { ModuleMarkdown } from "./module-markdown";

it("shows the alt text without loading README media", () => {
  const { container } = render(
    <ModuleMarkdown>{"![Build status](https://docs.example/badge.png)"}</ModuleMarkdown>,
  );
  expect(screen.getByText("Build status")).toBeTruthy();
  expect(container.querySelector("img, iframe, [src], [srcset]")).toBeNull();
});
