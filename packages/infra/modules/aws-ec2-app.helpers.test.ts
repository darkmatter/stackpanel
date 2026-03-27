// @ts-nocheck
import { describe, expect, test } from "bun:test";
import {
  buildAlbTargets,
  buildSecurityGroupEgressResources,
  buildSecurityGroupIngressResources,
  sanitizeAwsName,
  toAwsTags,
} from "./aws-ec2-app.helpers";

describe("aws-ec2-app native helpers", () => {
  test("toAwsTags returns undefined for empty tags", () => {
    expect(toAwsTags(undefined)).toBeUndefined();
    expect(toAwsTags({})).toBeUndefined();
  });

  test("toAwsTags converts records into AWS tag objects", () => {
    expect(
      toAwsTags({
        Name: "stackpanel-staging",
        ManagedBy: "stackpanel-infra",
      }),
    ).toEqual([
      { Key: "Name", Value: "stackpanel-staging" },
      { Key: "ManagedBy", Value: "stackpanel-infra" },
    ]);
  });

  test("sanitizeAwsName normalizes invalid characters and truncates", () => {
    expect(sanitizeAwsName("stackpanel/staging_alb", 32)).toBe("stackpanel-staging-alb");
    expect(sanitizeAwsName("this-name-is-way-too-long-for-an-elb-resource", 32)).toBe(
      "this-name-is-way-too-long-for-an",
    );
  });

  test("buildAlbTargets emits instance target descriptions", () => {
    expect(buildAlbTargets(["i-abc", "i-def"], 8080)).toEqual([
      { Id: "i-abc", Port: 8080 },
      { Id: "i-def", Port: 8080 },
    ]);
  });

  test("buildSecurityGroupIngressResources expands ipv4, ipv6, and source groups", () => {
    expect(
      buildSecurityGroupIngressResources("sg-123", [
        {
          fromPort: 80,
          toPort: 80,
          protocol: "tcp",
          cidrBlocks: ["0.0.0.0/0"],
          ipv6CidrBlocks: ["::/0"],
          securityGroupIds: ["sg-source"],
          description: "web",
        },
      ]),
    ).toEqual([
      {
        GroupId: "sg-123",
        IpProtocol: "tcp",
        FromPort: 80,
        ToPort: 80,
        Description: "web",
        CidrIp: "0.0.0.0/0",
      },
      {
        GroupId: "sg-123",
        IpProtocol: "tcp",
        FromPort: 80,
        ToPort: 80,
        Description: "web",
        CidrIpv6: "::/0",
      },
      {
        GroupId: "sg-123",
        IpProtocol: "tcp",
        FromPort: 80,
        ToPort: 80,
        Description: "web",
        SourceSecurityGroupId: "sg-source",
      },
    ]);
  });

  test("buildSecurityGroupEgressResources expands destination group rules", () => {
    expect(
      buildSecurityGroupEgressResources("sg-123", [
        {
          fromPort: 0,
          toPort: 0,
          protocol: "-1",
          securityGroupIds: ["sg-dest"],
        },
      ]),
    ).toEqual([
      {
        GroupId: "sg-123",
        IpProtocol: "-1",
        FromPort: 0,
        ToPort: 0,
        DestinationSecurityGroupId: "sg-dest",
      },
    ]);
  });
});
