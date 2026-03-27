import { createFileRoute } from "@tanstack/react-router";
import { FeatureFlagsPanel } from "@/components/studio/panels/feature-flags-panel";

export const Route = createFileRoute("/studio/feature-flags")({
  component: FeatureFlagsRoute,
});

function FeatureFlagsRoute() {
  return <FeatureFlagsPanel />;
}
