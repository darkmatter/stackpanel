import { describe, expect, it } from "vitest";
import { isStudioHost } from "./studio-host";

describe("isStudioHost", () => {
	it("matches studio and local dev hosts", () => {
		expect(isStudioHost("local.stackpanel.com")).toBe(true);
		expect(isStudioHost("local.stackpanel.dev")).toBe(true);
		expect(isStudioHost("local.staging.stackpanel.com")).toBe(true);
		expect(isStudioHost("localhost")).toBe(true);
		expect(isStudioHost("127.0.0.1")).toBe(true);
	});

	it("does not match marketing apex", () => {
		expect(isStudioHost("stackpanel.com")).toBe(false);
		expect(isStudioHost("www.stackpanel.com")).toBe(false);
		expect(isStudioHost("docs.stackpanel.com")).toBe(false);
	});

	it("rejects spoofed studio hostnames", () => {
		expect(isStudioHost("local.stackpanel.com.evil.example")).toBe(false);
		expect(isStudioHost("x.local.stackpanel.com")).toBe(false);
	});
});
