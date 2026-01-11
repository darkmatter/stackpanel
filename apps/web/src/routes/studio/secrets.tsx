import { createFileRoute } from "@tanstack/react-router";
import { SecretsPanel } from "@/components/studio/panels/secrets-panel";

export const Route = createFileRoute("/studio/secrets")({
  component: SecretsRoute,
});

function SecretsRoute() {
  return <SecretsPanel />;
}
