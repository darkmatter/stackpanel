/**
 * Modules Page
 *
 * Browse and configure Stackpanel modules. This is the new unified module
 * browser that replaces the old extensions system.
 *
 * Modules provide:
 * - File generation
 * - Scripts/commands
 * - Tasks
 * - Health checks
 * - Services
 * - Secrets management
 * - Packages
 * - App configuration
 * - UI panels
 */

import { createFileRoute } from "@tanstack/react-router";
import { ModulesPanel } from "@/components/studio/panels/modules/modules-panel";

export const Route = createFileRoute("/studio/modules")({
  component: ModulesPage,
});

function ModulesPage() {
  return (
    <div className="container mx-auto py-8">
      <ModulesPanel />
    </div>
  );
}
