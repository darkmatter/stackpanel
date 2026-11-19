import { fireEvent, render, screen } from "@testing-library/react";
import { expect, it } from "vite-plus/test";
import { HelpButton } from "./help-button";

it("opens a panel README as Markdown in its help dialog", async () => {
  render(
    <HelpButton title="Release module" readme={"## Deploy locally\n\nRun `stack release`."} />,
  );
  fireEvent.click(screen.getByRole("button", { name: "Help" }));
  expect(await screen.findByRole("dialog", { name: "Release module" })).toBeTruthy();
  expect(screen.getByRole("heading", { name: "Deploy locally" })).toBeTruthy();
  expect(screen.getByText("stack release").tagName).toBe("CODE");
});
