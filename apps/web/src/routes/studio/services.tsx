import { createFileRoute } from "@tanstack/react-router";
import { ServicesPanel } from "@/components/studio/panels/services-panel";

export const Route = createFileRoute("/studio/services")({
  component: ServicesRoute,
});

function ServicesRoute() {
  return <ServicesPanel />;
}
