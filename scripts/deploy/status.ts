import {
  getLatestWebInstance,
  getSsmInstanceInfo,
  probeHealth,
  runSsmCommands,
} from "./lib";

const [, , app = "web", region = "us-west-2"] = process.argv;

const instance = getLatestWebInstance(region);
if (!instance) {
  console.log(`No ${app} instance found in region ${region}.`);
  process.exit(0);
}

const host = instance.publicDnsName || instance.publicIpAddress;
const health = probeHealth(host);
const ssm = getSsmInstanceInfo(instance.instanceId, region);

console.log(`App:          ${app}`);
console.log(`Region:       ${region}`);
if (instance.stage) {
  console.log(`Stage:        ${instance.stage}`);
}
console.log(`Source:       ${instance.source}`);
console.log(`Instance ID:  ${instance.instanceId}`);
console.log(`State:        ${instance.state}`);
console.log(`Launched:     ${instance.launchTime}`);
if (instance.publicDnsName) {
  console.log(`Public DNS:   ${instance.publicDnsName}`);
}
if (instance.publicIpAddress) {
  console.log(`Public IP:    ${instance.publicIpAddress}`);
}
if (instance.privateIpAddress) {
  console.log(`Private IP:   ${instance.privateIpAddress}`);
}
if (health.url) {
  console.log(`Health URL:   ${health.url}`);
  console.log(`Health:       ${health.status}`);
  if (health.body) {
    const truncated = health.body.length > 200 ? health.body.slice(0, 200) + "..." : health.body;
    console.log(`Health Body:  ${truncated}`);
  }
  if (health.error) {
    console.log(`Health Error: ${health.error}`);
  }
}

if (ssm) {
  console.log(`SSM Ping:     ${ssm.PingStatus ?? "unknown"}`);
  console.log(`SSM Agent:    ${ssm.AgentVersion ?? "unknown"}`);
  if (ssm.PlatformName || ssm.PlatformVersion) {
    console.log(
      `Platform:     ${ssm.PlatformName ?? "unknown"} ${ssm.PlatformVersion ?? ""}`.trimEnd(),
    );
  }
}

if (ssm?.PingStatus === "Online") {
  const remote = runSsmCommands(instance.instanceId, region, "deploy-status", [
    "set -eu",
    "systemctl is-active stackpanel-web.service || true",
    "systemctl --no-pager --full status stackpanel-web.service || true",
  ]);

  console.log(
    `SSM Cmd:      ${remote.StatusDetails || remote.Status || "unknown"}`,
  );

  const statusOutput = remote.StandardOutputContent?.trim();
  const statusError = remote.StandardErrorContent?.trim();

  if (statusOutput) {
    console.log("---- remote stdout ----");
    console.log(statusOutput);
  }
  if (statusError) {
    console.log("---- remote stderr ----");
    console.log(statusError);
  }
}
