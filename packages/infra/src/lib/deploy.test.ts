import { describe, expect, test } from "bun:test";
import { usesLocalAlchemyState } from "./deploy";

describe("usesLocalAlchemyState", () => {
  test("uses filesystem state only for the local dev stage", () => {
    expect(usesLocalAlchemyState({ stage: "dev", appEnv: "dev" })).toBe(true);
  });

  test("uses shared state for PR previews and named non-production stages", () => {
    expect(usesLocalAlchemyState({ stage: "pr-42", appEnv: "dev" })).toBe(false);
    expect(usesLocalAlchemyState({ stage: "preview", appEnv: "dev" })).toBe(false);
  });

  test("uses shared state for staging and production", () => {
    expect(usesLocalAlchemyState({ stage: "staging", appEnv: "staging" })).toBe(
      false,
    );
    expect(usesLocalAlchemyState({ stage: "production", appEnv: "prod" })).toBe(
      false,
    );
  });
});
