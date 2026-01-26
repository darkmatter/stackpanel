# ==============================================================================
# Deployment Module
#
# Aggregates all deployment provider modules (currently: Fly.io).
# Future providers can be added here (e.g., AWS ECS, Railway, Render).
# ==============================================================================
{
  imports = [
    ./fly # Fly.io deployment
  ];
}
