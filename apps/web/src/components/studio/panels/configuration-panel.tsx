"use client";

import { TooltipProvider } from "@ui/tooltip";
import { useSearch } from "@tanstack/react-router";
import { useAgentContext } from "@/lib/agent-provider";
import {
  AwsSection,
  CacheSection,
  GitHubSection,
  IdeSection,
  StarshipSection,
  StepCaSection,
  getConfigurationSections,
  getDefaultSectionId,
  useConfiguration,
} from "./configuration";
import { PanelHeader } from "./shared/panel-header";
import { StudioPanel } from "./shared/studio-panel";
import { useStudioPanels } from "./shared/use-studio-panels";

function BuiltInSection({ id }: { id: string }) {
  const config = useConfiguration();
  switch (id) {
    case "github":
      return <GitHubSection config={config} />;
    case "step-ca":
      return <StepCaSection config={config} />;
    case "aws":
      return <AwsSection config={config} />;
    case "starship":
      return <StarshipSection config={config} />;
    case "ide":
      return <IdeSection config={config} />;
    case "cache":
      return <CacheSection config={config} />;
  }
  return null;
}

export function ConfigurationPanel() {
  const { section } = useSearch({ from: "/studio/configuration" });
  const { isConnected } = useAgentContext();
  const { panels, config, isLoading, error } = useStudioPanels();
  const activeId = section === "vscode" ? "ide" : (section ?? getDefaultSectionId());
  const current = getConfigurationSections(panels).find(({ id }) => id === activeId);
  let notice: string | undefined;
  if (!isConnected) notice = "Connect to the agent to view configuration.";
  else if (error) notice = `Could not load configuration: ${error.message}`;
  else if (isLoading) notice = "Loading configuration sections…";
  else if (!config) notice = "Project configuration is unavailable.";
  else if (!current) notice = "This configuration section is not available.";

  return (
    <TooltipProvider>
      <div className="space-y-6">
        <PanelHeader
          title={current?.label ?? "Configuration"}
          description={current?.description ?? "Manage Stackpanel settings"}
          guideKey="configuration"
        />
        {notice ? (
          <p role={error ? "alert" : "status"} className="text-sm text-muted-foreground">
            {notice}
          </p>
        ) : current?.panel ? (
          <StudioPanel key={current.id} panel={current.panel} />
        ) : current ? (
          <div className="max-w-2xl">
            <BuiltInSection id={current.id} />
          </div>
        ) : null}
      </div>
    </TooltipProvider>
  );
}
