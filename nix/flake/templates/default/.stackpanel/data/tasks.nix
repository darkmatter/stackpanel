# tasks.nix - Workspace tasks (Turborepo pipeline)
# type: sp-task
# See: https://stackpanel.dev/docs/tasks
{
  # Example tasks (mirrors turbo.json options):
  # build = {
  #   exec = "npm run compile";
  #   description = "Build all packages";
  #   dependsOn = [ "^build" "deps" ];
  #   outputs = [ "dist/**" ];
  #   inputs = [ "$TURBO_DEFAULT$" ];
  # };
  #
  # dev = {
  #   description = "Start development servers";
  #   persistent = true;
  #   cache = false;
  # };
  #
  # test = {
  #   exec = "vitest run";
  #   dependsOn = [ "build" ];
  #   outputs = [ "coverage/**" ];
  # };
}
