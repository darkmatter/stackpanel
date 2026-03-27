export interface RuleConfigLike {
  fromPort: number;
  toPort: number;
  protocol?: string;
  cidrBlocks?: string[];
  ipv6CidrBlocks?: string[];
  securityGroupIds?: string[];
  description?: string | null;
}

export function toAwsTags(tags?: Record<string, string>) {
  if (!tags || Object.keys(tags).length === 0) {
    return undefined;
  }

  return Object.entries(tags).map(([Key, Value]) => ({
    Key,
    Value,
  }));
}

export function sanitizeAwsName(name: string, maxLength = 32) {
  return name.replace(/[^a-zA-Z0-9-]/g, "-").slice(0, maxLength);
}

export function buildAlbTargets(instanceIds: string[], port?: number) {
  return instanceIds.map((Id) => ({
    Id,
    ...(port === undefined ? {} : { Port: port }),
  }));
}

export function buildSecurityGroupIngressResources(
  groupId: string | undefined,
  rules: RuleConfigLike[],
) {
  return rules.flatMap((rule) => [
    ...(rule.cidrBlocks ?? []).map((cidr) => ({
      ...(groupId ? { GroupId: groupId } : {}),
      IpProtocol: rule.protocol ?? "tcp",
      FromPort: rule.fromPort,
      ToPort: rule.toPort,
      Description: rule.description ?? undefined,
      CidrIp: cidr,
    })),
    ...(rule.ipv6CidrBlocks ?? []).map((cidr) => ({
      ...(groupId ? { GroupId: groupId } : {}),
      IpProtocol: rule.protocol ?? "tcp",
      FromPort: rule.fromPort,
      ToPort: rule.toPort,
      Description: rule.description ?? undefined,
      CidrIpv6: cidr,
    })),
    ...(rule.securityGroupIds ?? []).map((securityGroupId) => ({
      ...(groupId ? { GroupId: groupId } : {}),
      IpProtocol: rule.protocol ?? "tcp",
      FromPort: rule.fromPort,
      ToPort: rule.toPort,
      Description: rule.description ?? undefined,
      SourceSecurityGroupId: securityGroupId,
    })),
  ]);
}

export function buildSecurityGroupEgressResources(
  groupId: string | undefined,
  rules: RuleConfigLike[],
) {
  return rules.flatMap((rule) => [
    ...(rule.cidrBlocks ?? []).map((cidr) => ({
      ...(groupId ? { GroupId: groupId } : {}),
      IpProtocol: rule.protocol ?? "tcp",
      FromPort: rule.fromPort,
      ToPort: rule.toPort,
      Description: rule.description ?? undefined,
      CidrIp: cidr,
    })),
    ...(rule.ipv6CidrBlocks ?? []).map((cidr) => ({
      ...(groupId ? { GroupId: groupId } : {}),
      IpProtocol: rule.protocol ?? "tcp",
      FromPort: rule.fromPort,
      ToPort: rule.toPort,
      Description: rule.description ?? undefined,
      CidrIpv6: cidr,
    })),
    ...(rule.securityGroupIds ?? []).map((securityGroupId) => ({
      ...(groupId ? { GroupId: groupId } : {}),
      IpProtocol: rule.protocol ?? "tcp",
      FromPort: rule.fromPort,
      ToPort: rule.toPort,
      Description: rule.description ?? undefined,
      DestinationSecurityGroupId: securityGroupId,
    })),
  ]);
}
