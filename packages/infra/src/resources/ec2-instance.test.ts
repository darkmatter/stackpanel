// @ts-nocheck
import { describe, expect, test } from "bun:test";
import {
  coerceEc2InstanceState,
  isEc2InstanceReady,
  normalizeEc2InstanceProps,
  requiresEc2InstanceReplacement,
  shouldReuseEc2InstanceState,
} from "./ec2-instance";

describe("Ec2Instance replacement planning", () => {
  test("ignores equivalent props when comparing desired state snapshots", () => {
    const previous = normalizeEc2InstanceProps({
      name: "web",
      ami: "ami-123",
      instanceType: "t3.small",
      subnetId: "subnet-123",
      securityGroupIds: ["sg-123"],
      iamInstanceProfile: "web-profile",
      userData: "bootstrap-v1",
      tags: { Name: "web", Stage: "staging" },
    });

    const next = normalizeEc2InstanceProps({
      name: "web",
      ami: "ami-123",
      instanceType: "t3.small",
      subnetId: "subnet-123",
      securityGroupIds: ["sg-123"],
      iamInstanceProfile: "web-profile",
      userData: "bootstrap-v1",
      tags: { Stage: "staging", Name: "web" },
    });

    expect(requiresEc2InstanceReplacement(previous, next)).toBe(false);
  });

  test("replaces when bootstrap user data changes", () => {
    const previous = normalizeEc2InstanceProps({
      name: "web",
      ami: "ami-123",
      instanceType: "t3.small",
      subnetId: "subnet-123",
      securityGroupIds: ["sg-123"],
      iamInstanceProfile: "web-profile",
      userData: "bootstrap-v1",
    });

    const next = normalizeEc2InstanceProps({
      name: "web",
      ami: "ami-123",
      instanceType: "t3.small",
      subnetId: "subnet-123",
      securityGroupIds: ["sg-123"],
      iamInstanceProfile: "web-profile",
      userData: "bootstrap-v2",
    });

    expect(requiresEc2InstanceReplacement(previous, next)).toBe(true);
  });

  test("replaces when network identity changes", () => {
    const previous = normalizeEc2InstanceProps({
      name: "web",
      ami: "ami-123",
      instanceType: "t3.small",
      subnetId: "subnet-123",
      securityGroupIds: ["sg-123"],
    });

    const next = normalizeEc2InstanceProps({
      name: "web",
      ami: "ami-123",
      instanceType: "t3.small",
      subnetId: "subnet-123",
      securityGroupIds: ["sg-456"],
    });

    expect(requiresEc2InstanceReplacement(previous, next)).toBe(true);
  });

  test("adopts legacy AWS control output without forcing recreation", () => {
    const state = coerceEc2InstanceState({
      id: "i-legacy",
      PublicIp: "1.2.3.4",
      PrivateIp: "10.0.0.10",
      PublicDnsName: "ec2-1-2-3-4.compute.amazonaws.com",
      desiredState: {
        ImageId: "ami-123",
        InstanceType: "t3.small",
        SubnetId: "subnet-123",
        SecurityGroupIds: ["sg-123"],
        IamInstanceProfile: "web-profile",
        UserData: "bootstrap-v1",
        BlockDeviceMappings: [
          {
            Ebs: {
              VolumeSize: 20,
            },
          },
        ],
        Tags: [
          { Key: "Stage", Value: "staging" },
          { Key: "Name", Value: "web" },
        ],
      },
    });

    expect(state.instanceId).toBe("i-legacy");
    expect(state.publicIp).toBe("1.2.3.4");
    expect(state.publicDns).toBe("ec2-1-2-3-4.compute.amazonaws.com");
    expect(state.propsSnapshot).toEqual(
      normalizeEc2InstanceProps({
        name: "legacy",
        ami: "ami-123",
        instanceType: "t3.small",
        subnetId: "subnet-123",
        securityGroupIds: ["sg-123"],
        iamInstanceProfile: "web-profile",
        userData: "bootstrap-v1",
        rootVolumeSize: 20,
        tags: {
          Name: "web",
          Stage: "staging",
        },
      }),
    );
  });

  test("waits for public endpoint details when a public instance is expected", () => {
    expect(
      isEc2InstanceReady(
        {
          State: { Name: "running" },
          PublicIpAddress: "1.2.3.4",
          PublicDnsName: "ec2-1-2-3-4.compute.amazonaws.com",
        },
        true,
      ),
    ).toBe(true);

    expect(
      isEc2InstanceReady(
        {
          State: { Name: "running" },
          PublicIpAddress: "1.2.3.4",
          PublicDnsName: "",
        },
        true,
      ),
    ).toBe(true);

    expect(
      isEc2InstanceReady(
        {
          State: { Name: "pending" },
          PublicIpAddress: "1.2.3.4",
          PublicDnsName: "ec2-1-2-3-4.compute.amazonaws.com",
        },
        true,
      ),
    ).toBe(false);
  });

  test("does not reuse prior output during replacement creates", () => {
    expect(
      shouldReuseEc2InstanceState("create", {
        instanceId: "i-old",
        state: "terminated",
      }),
    ).toBe(false);

    expect(
      shouldReuseEc2InstanceState("update", {
        instanceId: "i-old",
        state: "running",
      }),
    ).toBe(true);
  });
});
