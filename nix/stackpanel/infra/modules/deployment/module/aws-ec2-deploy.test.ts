import { describe, expect, test } from "bun:test";
import {
  buildUserData,
  deriveRuntimeLayout,
} from "./aws-ec2-deploy";

describe("deriveRuntimeLayout", () => {
  test("derives runtime paths and service names from app name", () => {
    expect(deriveRuntimeLayout("web")).toEqual({
      appRoot: "/opt/stackpanel-web",
      archivePath: "/tmp/stackpanel-web-release.tar.gz",
      envFile: "/etc/stackpanel-web.env",
      releaseRoot: "/opt/stackpanel-web/release",
      serviceName: "stackpanel-web.service",
      slug: "web",
    });

    expect(deriveRuntimeLayout("docs_site")).toEqual({
      appRoot: "/opt/stackpanel-docs-site",
      archivePath: "/tmp/stackpanel-docs-site-release.tar.gz",
      envFile: "/etc/stackpanel-docs-site.env",
      releaseRoot: "/opt/stackpanel-docs-site/release",
      serviceName: "stackpanel-docs-site.service",
      slug: "docs-site",
    });
  });
});

describe("buildUserData", () => {
  test("uses the derived runtime layout instead of hard-coded web paths", () => {
    const script = buildUserData({
      appName: "docs_site",
      artifactBucket: "bucket-name",
      artifactKey: "docs/staging/release.tar.gz",
      parameterPath: "/stackpanel/staging/docs-runtime",
      port: 8080,
      region: "us-west-2",
      rootVolumeSize: 30,
    });

    expect(script).toContain('APP_ROOT="/opt/stackpanel-docs-site"');
    expect(script).toContain('ENV_FILE="/etc/stackpanel-docs-site.env"');
    expect(script).toContain('ARCHIVE_PATH="/tmp/stackpanel-docs-site-release.tar.gz"');
    expect(script).toContain("/etc/systemd/system/stackpanel-docs-site.service");
    expect(script).toContain("ExecStart=/usr/bin/node /opt/stackpanel-docs-site/release/.output/server/index.mjs");
    expect(script).toContain("PORT=8080");
  });
});
