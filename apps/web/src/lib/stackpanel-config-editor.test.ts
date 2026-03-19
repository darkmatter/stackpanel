import { describe, expect, it } from "vitest";
import {
  buildLocalConfigJsonSchema,
  renderNixAttrset,
  renderNixFile,
} from "./stackpanel-config-editor";

describe("stackpanel-config-editor", () => {
  it("builds a nested JSON schema from flat option docs", () => {
    const schema = buildLocalConfigJsonSchema({
      "stackpanel.apps": {
        type: "attribute set of (submodule)",
        description: "Apps",
      },
      "stackpanel.apps.<name>.deployment.host": {
        type: 'null or one of "cloudflare", "fly", "vercel", "aws"',
        description: "Deployment target",
      },
      "stackpanel.apps.<name>.tls": {
        type: "boolean",
        description: "Enable TLS",
      },
      "stackpanel.devshell.packages": {
        type: "list of string",
        description: "Packages",
      },
    });

    expect(schema).toMatchObject({
      type: "object",
      properties: {
        apps: {
          type: "object",
          additionalProperties: {
            type: "object",
            properties: {
              deployment: {
                type: "object",
                properties: {
                  host: {
                    type: ["string", "null"],
                    enum: ["cloudflare", "fly", "vercel", "aws", null],
                  },
                },
              },
              tls: {
                type: "boolean",
              },
            },
          },
        },
        devshell: {
          type: "object",
          properties: {
            packages: {
              type: "array",
              items: { type: "string" },
            },
          },
        },
      },
    });
  });

  it("renders nested JSON data back to a Nix attrset", () => {
    expect(
      renderNixAttrset({
        apps: {
          web: {
            domain: "docs",
            tls: true,
          },
        },
        variables: {
          "/var/postgres-url": {
            value: 'ref+sops://.stack/secrets/dev.yaml#/postgres_url',
          },
        },
      }),
    ).toBe(`{
  apps = {
    web = {
      domain = "docs";
      tls = true;
    };
  };
  variables = {
    "/var/postgres-url" = {
      value = "ref+sops://.stack/secrets/dev.yaml#/postgres_url";
    };
  };
}
`);
  });

  it("preserves a function wrapper when rendering a full config file", () => {
    expect(
      renderNixFile(
        {
          apps: {
            web: {
              tls: true,
            },
          },
        },
        {
          existingSource: `# config.nix\n{ config, ... }:\n{\n  apps = { };\n}\n`,
          defaultFunctionHeader: "{ config, ... }:",
        },
      ),
    ).toBe(`# config.nix
{ config, ... }:
{
  apps = {
    web = {
      tls = true;
    };
  };
}
`);
  });

  it("creates a new local overrides file as a plain attrset by default", () => {
    expect(
      renderNixFile(
        {
          debug: true,
        },
        {
          existingSource: "",
          defaultFunctionHeader: null,
        },
      ),
    ).toBe(`{
  debug = true;
}
`);
  });
});
