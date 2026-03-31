// @ts-nocheck
import { afterEach, describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import Infra from "./index.ts";

const ORIGINAL_ENV = { ...process.env };

afterEach(() => {
  process.env = { ...ORIGINAL_ENV };
});

describe("Infra.inputs", () => {
  test("preserves app ids while normalizing structured input keys", () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "stackpanel-infra-"));
    const inputsPath = path.join(tempDir, "infra-inputs.json");

    fs.writeFileSync(
      inputsPath,
      JSON.stringify({
        "aws-ec2-app": {
          apps: {
            "stackpanel-staging": {
              "instance-count": 2,
              "instance-type": "t2.micro",
              iam: {
                "role-name": "stackpanel-staging-ec2-role",
                "instance-profile-name": "stackpanel-staging-ec2-role-profile",
              },
              tags: {
                "managed-by": "stackpanel-infra",
              },
              ssm: {
                parameters: {
                  "API-TOKEN": "secret",
                },
              },
            },
          },
        },
      }),
    );

    process.env.STACKPANEL_ROOT = tempDir;
    process.env.STACKPANEL_INFRA_INPUTS = inputsPath;

    const infra = new Infra("aws-ec2-app");
    const inputs = infra.inputs<{
      apps: Record<
        string,
        {
          instanceCount?: number;
          instanceType?: string;
          iam?: {
            roleName?: string;
            instanceProfileName?: string;
          };
          tags?: Record<string, string>;
          ssm?: {
            parameters?: Record<string, string>;
          };
        }
      >;
    }>();

    expect(inputs.apps["stackpanel-staging"]).toBeDefined();
    expect(inputs.apps.stackpanelStaging).toBeUndefined();
    expect(inputs.apps["stackpanel-staging"]?.instanceCount).toBe(2);
    expect(inputs.apps["stackpanel-staging"]?.instanceType).toBe("t2.micro");
    expect(inputs.apps["stackpanel-staging"]?.iam?.roleName).toBe(
      "stackpanel-staging-ec2-role",
    );
    expect(inputs.apps["stackpanel-staging"]?.iam?.instanceProfileName).toBe(
      "stackpanel-staging-ec2-role-profile",
    );
    expect(inputs.apps["stackpanel-staging"]?.tags?.["managed-by"]).toBe(
      "stackpanel-infra",
    );
    expect(inputs.apps["stackpanel-staging"]?.ssm?.parameters?.["API-TOKEN"]).toBe(
      "secret",
    );
  });
});
