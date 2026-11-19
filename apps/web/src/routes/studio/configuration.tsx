import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { ConfigurationPanel } from "@/components/studio/panels/configuration-panel";

const configurationSearchSchema = z.object({
  section: z.string().optional(),
});

export const Route = createFileRoute("/studio/configuration")({
  component: ConfigurationRoute,
  validateSearch: configurationSearchSchema,
});

function ConfigurationRoute() {
  return <ConfigurationPanel />;
}
