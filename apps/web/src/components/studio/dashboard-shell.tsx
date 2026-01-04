"use client";

import { useState } from "react";
import { DashboardHeader } from "./dashboard-header";
import { DashboardSidebar } from "./dashboard-sidebar";
import { DatabasesPanel } from "./panels/databases-panel";
import { DevShellsPanel } from "./panels/dev-shells-panel";
import { NetworkPanel } from "./panels/network-panel";
import { OverviewPanel } from "./panels/overview-panel";
import { SecretsPanel } from "./panels/secrets-panel";
import { ServicesPanel } from "./panels/services-panel";
import { TeamPanel } from "./panels/team-panel";
import { TerminalPanel } from "./panels/terminal-panel";

export type PanelType =
	| "overview"
	| "services"
	| "databases"
	| "secrets"
	| "devshells"
	| "team"
	| "network"
	| "terminal";

export function DashboardShell() {
	const [activePanel, setActivePanel] = useState<PanelType>("overview");
	const [sidebarCollapsed, setSidebarCollapsed] = useState(false);

	const renderPanel = () => {
		switch (activePanel) {
			case "overview":
				return <OverviewPanel onNavigate={setActivePanel} />;
			case "services":
				return <ServicesPanel />;
			case "databases":
				return <DatabasesPanel />;
			case "secrets":
				return <SecretsPanel />;
			case "devshells":
				return <DevShellsPanel />;
			case "team":
				return <TeamPanel />;
			case "network":
				return <NetworkPanel />;
			case "terminal":
				return <TerminalPanel />;
			default:
				return <OverviewPanel onNavigate={setActivePanel} />;
		}
	};

	return (
		<div className="flex h-screen bg-background">
			<DashboardSidebar
				activePanel={activePanel}
				collapsed={sidebarCollapsed}
				onPanelChange={setActivePanel}
				onToggleCollapse={() => setSidebarCollapsed(!sidebarCollapsed)}
			/>
			<div className="flex flex-1 flex-col overflow-hidden">
				<DashboardHeader activePanel={activePanel} />
				<main className="flex-1 overflow-auto p-6">{renderPanel()}</main>
			</div>
		</div>
	);
}
