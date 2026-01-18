"use client";

import { Terminal } from "lucide-react";
import { AgentConnect } from "@/components/agent-connect";
import { useSetupContext } from "../setup-context";
import { StepCard } from "../step-card";
import type { SetupStep } from "../types";

export function ConnectAgentStep() {
	const { expandedStep, setExpandedStep, isConnected, goToStep } =
		useSetupContext();

	const step: SetupStep = {
		id: "connect-agent",
		title: "Connect to Agent",
		description: "Install the CLI and connect to your local Stackpanel agent",
		status: isConnected ? "complete" : "incomplete",
		required: true,
		icon: <Terminal className="h-5 w-5" />,
	};

	return (
		<StepCard
			step={step}
			isExpanded={expandedStep === "connect-agent"}
			onToggle={() =>
				setExpandedStep(
					expandedStep === "connect-agent" ? null : "connect-agent",
				)
			}
		>
			<AgentConnect
				onConnected={() => {
					goToStep("project-info");
				}}
			/>
		</StepCard>
	);
}
