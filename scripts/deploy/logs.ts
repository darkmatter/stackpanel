import {
  getLatestWebInstance,
  runSsmCommands,
} from "./lib";

const [, , region = "us-west-2", lines = "120"] = process.argv;

const instance = getLatestWebInstance(region);
if (!instance) {
  console.log("No web instance found.");
  process.exit(0);
}

console.log(`App:          web`);
console.log(`Instance ID:  ${instance.instanceId}`);
console.log(`Region:       ${region}`);
console.log(`Lines:        ${lines}`);
console.log();

const invocation = runSsmCommands(instance.instanceId, region, "deploy-logs", [
  "set -eu",
  `journalctl -u stackpanel-web.service --no-pager -n ${lines} 2>/dev/null || tail -n ${lines} /var/log/user-data.log 2>/dev/null || echo 'No logs found'`,
]);

const stdout = invocation.StandardOutputContent?.trim();
const stderr = invocation.StandardErrorContent?.trim();

if (stdout) {
  console.log(stdout);
}
if (stderr) {
  console.error(stderr);
}
