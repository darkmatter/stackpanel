import { describe, expect, test } from "bun:test";
import { resolveEc2ArtifactConfig } from "./artifact";

describe("resolveEc2ArtifactConfig", () => {
  test("does not require an artifact for nixos deploys", () => {
    expect(
      resolveEc2ArtifactConfig({
        osType: "nixos",
        stage: "staging",
        env: {},
        globalArtifact: {},
      }),
    ).toBeNull();
  });

  test("derives the artifact location for amazon-linux deploys", () => {
    expect(
      resolveEc2ArtifactConfig({
        osType: "amazon-linux",
        stage: "staging",
        env: {
          EC2_ARTIFACT_VERSION: "abc123",
        },
        globalArtifact: {
          bucket: "stackpanel-artifacts",
          keyPrefix: "web",
        },
      }),
    ).toEqual({
      artifactBucket: "stackpanel-artifacts",
      artifactKey: "web/staging/abc123/release.tar.gz",
      artifactVersion: "abc123",
    });
  });

  test("still requires an artifact bucket for amazon-linux deploys", () => {
    expect(() =>
      resolveEc2ArtifactConfig({
        osType: "amazon-linux",
        stage: "staging",
        env: {
          EC2_ARTIFACT_VERSION: "abc123",
        },
        globalArtifact: {},
      }),
    ).toThrow(
      "EC2_ARTIFACT_BUCKET is required unless stackpanel.deployment.aws.artifact.bucket is configured",
    );
  });
});
