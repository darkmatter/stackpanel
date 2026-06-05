# ==============================================================================
# integrations/default.nix
#
# Aggregator for service, cloud, and deployment integration modules.
# Core stackpanel imports this single entry point; sub-features enable
# themselves via stackpanel.* options.
# ==============================================================================
{ ... }:
{
  imports = [
    ./services
    ./docker
    ./containers
    ./deployment
    ./infra
    ./sst
  ];
}
