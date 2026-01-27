import { createFileRoute } from "@tanstack/react-router";
import { PanelsPanel } from "@/components/studio/panels/panels-panel";
import { z } from "zod";

const panelsSearchSchema = z.object({
  module: z.string().optional(),
});

export const Route = createFileRoute("/studio/panels")({
  component: PanelsPage,
  validateSearch: panelsSearchSchema,
});

function PanelsPage() {
  return (
    <div className="container mx-auto py-8">
      <PanelsPanel />
    </div>
  );
}
