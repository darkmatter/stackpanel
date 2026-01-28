# ==============================================================================
# meta.nix - Cloudflare Deployment Module Metadata
# ==============================================================================
{
  id = "deployment-cloudflare";
  name = "Cloudflare Workers";
  description = ''
    Deploy apps to Cloudflare Workers using Alchemy.
    
    Cloudflare Workers run at the edge on V8 isolates, providing:
    - Global distribution with low latency
    - Automatic scaling (pay-per-request)
    - No cold starts (always-on workers)
    
    Best for:
    - Web apps with global users
    - API endpoints
    - Static sites with edge functions
    
    Uses Alchemy for IaC, which generates alchemy.run.ts resources.
  '';
  category = "deployment";
  priority = 100;

  # This is an appModule - adds options to each app
  appModule = true;

  # Dependencies
  requires = [ ];
  optionalDependencies = [ "containers" ];

  # UI configuration
  ui = {
    icon = "cloud";
    color = "orange";
    panel = {
      enable = true;
      title = "Cloudflare";
      description = "Cloudflare Workers deployment";
    };
  };
}
