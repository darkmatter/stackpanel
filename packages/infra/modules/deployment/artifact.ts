export interface Ec2ArtifactConfig {
  artifactBucket: string;
  artifactKey: string;
  artifactVersion?: string;
}

export interface ResolveEc2ArtifactConfigInput {
  osType: "amazon-linux" | "nixos";
  stage: string;
  env: Record<string, string | undefined>;
  globalArtifact: {
    bucket?: string | null;
    keyPrefix?: string | null;
  };
}

export function resolveEc2ArtifactConfig(
  input: ResolveEc2ArtifactConfigInput,
): Ec2ArtifactConfig | null {
  if (input.osType === "nixos") {
    return null;
  }

  const artifactVersion = input.env.EC2_ARTIFACT_VERSION;
  const artifactBucket = input.env.EC2_ARTIFACT_BUCKET ?? input.globalArtifact.bucket;
  const artifactKey = input.env.EC2_ARTIFACT_KEY
    ?? (
      artifactVersion
        ? `${input.globalArtifact.keyPrefix ?? "web"}/${input.stage}/${artifactVersion}/release.tar.gz`
        : undefined
    );

  if (!artifactBucket) {
    throw new Error(
      "EC2_ARTIFACT_BUCKET is required unless stackpanel.deployment.aws.artifact.bucket is configured",
    );
  }

  if (!artifactKey) {
    throw new Error(
      "EC2_ARTIFACT_KEY is required unless EC2_ARTIFACT_VERSION and stackpanel.deployment.aws.artifact.keyPrefix are available",
    );
  }

  return {
    artifactBucket,
    artifactKey,
    artifactVersion,
  };
}
