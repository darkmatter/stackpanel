"use client";

import { TooltipProvider } from "@ui/tooltip";
import { useSearch } from "@tanstack/react-router";
import {
  CONFIGURATION_SECTIONS,
  getDefaultSectionId,
  useConfiguration,
} from "./configuration";
import { PanelHeader } from "./shared/panel-header";
import {
  AwsSection,
  CacheSection,
  GitHubSection,
  StarshipSection,
  StepCaSection,
  VscodeSection,
} from "./configuration";

export function ConfigurationPanel() {
  const config = useConfiguration();
  const search = useSearch({ from: "/studio/configuration" });
  const activeSection =
    (search as { section?: string }).section ?? getDefaultSectionId();

  // Find the current section metadata
  const currentSection = CONFIGURATION_SECTIONS.find(
    (section) => section.id === activeSection,
  );

  // Render the active section
  function renderSection() {
    switch (activeSection) {
      case "github":
        return <GitHubSection config={config} />;
      case "step-ca":
        return <StepCaSection config={config} />;
      case "aws":
        return <AwsSection config={config} />;
      case "starship":
        return <StarshipSection config={config} />;
      case "vscode":
        return <VscodeSection config={config} />;
      case "cache":
        return <CacheSection config={config} />;
      default:
        return <GitHubSection config={config} />;
    }
  }

  return (
    <TooltipProvider>
      <div className="space-y-6">
        <PanelHeader
          title={currentSection?.label ?? "Configuration"}
          description={
            currentSection?.description ?? "Manage Stackpanel settings"
          }
          guideKey="configuration"
        />

        <div className="max-w-2xl">{renderSection()}</div>
      </div>
    </TooltipProvider>
  );
}
