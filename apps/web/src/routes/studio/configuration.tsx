import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { ConfigurationPanel } from "@/components/studio/panels/configuration-panel";
import { CONFIGURATION_SECTIONS } from "@/components/studio/panels/configuration";

const sectionIds = CONFIGURATION_SECTIONS.map((s) => s.id) as [
  string,
  ...string[],
];

const configurationSearchSchema = z.object({
  section: z.enum(sectionIds).optional(),
});

export const Route = createFileRoute("/studio/configuration")({
  component: ConfigurationRoute,
  validateSearch: configurationSearchSchema,
});

function ConfigurationRoute() {
  return <ConfigurationPanel />;
}
