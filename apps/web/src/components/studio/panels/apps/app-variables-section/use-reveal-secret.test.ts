import { describe, expect, it } from "vite-plus/test";
import { buildSopsFilePath, parseSopsRef } from "./use-reveal-secret";

describe("parseSopsRef", () => {
	it("splits a leading-slash group/key reference", () => {
		expect(parseSopsRef("/dev/postgres-url")).toEqual({
			group: "dev",
			key: "postgres-url",
		});
	});

	it("treats deeper paths as group/key (last segment is the key)", () => {
		expect(parseSopsRef("/shared/aws/access-key-id")).toEqual({
			group: "shared/aws",
			key: "access-key-id",
		});
	});

	it("returns null when the reference is missing or unparseable", () => {
		expect(parseSopsRef(undefined)).toBeNull();
		expect(parseSopsRef("")).toBeNull();
		expect(parseSopsRef("/")).toBeNull();
		expect(parseSopsRef("/just-a-key")).toBeNull();
	});
});

describe("buildSopsFilePath", () => {
	it("appends vars/<group>.sops.yaml to the project secrets directory", () => {
		expect(
			buildSopsFilePath("/repo/.stack/secrets", "dev"),
		).toBe("/repo/.stack/secrets/vars/dev.sops.yaml");
	});

	it("trims trailing slashes on the secrets directory", () => {
		expect(
			buildSopsFilePath("/repo/.stack/secrets/", "shared"),
		).toBe("/repo/.stack/secrets/vars/shared.sops.yaml");
	});
});
