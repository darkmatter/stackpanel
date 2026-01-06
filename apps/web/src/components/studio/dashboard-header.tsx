"use client";

import { Link } from "@tanstack/react-router";
import {
  ArrowLeft,
  Bell,
  Copy,
  ExternalLink,
  LogOut,
  Search,
  Settings,
  User,
} from "lucide-react";
import { toast } from "sonner";
import { AgentStatus } from "@/components/agent-connect";
import { ProjectSelector } from "@/components/project-selector";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { useAgentContext } from "@/lib/agent-provider";
import type { PanelType } from "./dashboard-shell";

const panelTitles: Record<PanelType, string> = {
  overview: "Overview",
  services: "Services",
  databases: "Databases",
  secrets: "Secrets",
  devshells: "Dev Shells",
  team: "Team",
  apps: "Apps",
  commands: "Commands",
  variables: "Variables",
  network: "Network",
  terminal: "Terminal",
};

interface DashboardHeaderProps {
  activePanel: PanelType;
}

export function DashboardHeader({ activePanel }: DashboardHeaderProps) {
  const {
    healthStatus,
    isConnected,
    isConnecting,
    token,
    projectRoot,
    pair,
    clearPairing,
    connect,
  } = useAgentContext();

  const agentLabel =
    healthStatus === "unavailable"
      ? "Agent offline"
      : isConnected
        ? "Agent connected"
        : isConnecting
          ? "Connecting..."
          : token
            ? "Agent paired"
            : "Agent not paired";

  const startAgentCommand = "stackpanel agent --debug";
  const startAgentCommandAlt = "stackpanel-agent --debug";

  return (
    <header className="flex h-16 items-center justify-between border-border border-b bg-card px-6">
      <div className="flex items-center gap-4">
        <Link to="/">
          <Button
            className="gap-2 text-muted-foreground hover:text-foreground"
            size="sm"
            variant="ghost"
          >
            <ArrowLeft className="h-4 w-4" />
            Exit Demo
          </Button>
        </Link>
        <div className="h-6 w-px bg-border" />
        <h1 className="font-semibold text-foreground text-lg">
          {panelTitles[activePanel]}
        </h1>
      </div>

      <div className="flex items-center gap-4">
        <div className="relative">
          <Search className="-translate-y-1/2 absolute top-1/2 left-3 h-4 w-4 text-muted-foreground" />
          <Input className="w-64 bg-secondary pl-9" placeholder="Search..." />
        </div>

        <div className="flex items-center gap-1">
          <Button
            className="text-muted-foreground hover:text-foreground"
            size="icon"
            variant="ghost"
          >
            <Bell className="h-5 w-5" />
          </Button>
          <Button
            className="text-muted-foreground hover:text-foreground"
            size="icon"
            variant="ghost"
          >
            <Settings className="h-5 w-5" />
          </Button>
        </div>

        <ProjectSelector />

        <div className="flex items-center gap-2 rounded-lg border border-border bg-secondary/50 px-3 py-1.5">
          <AgentStatus />
        </div>

        {/* <div className="flex items-center gap-2">
					<Badge
						className={
							healthStatus === "unavailable"
								? "border-destructive/30 text-destructive"
								: isConnected
									? "border-accent/30 text-accent"
									: "border-border text-muted-foreground"
						}
						variant="outline"
					>
						{agentLabel}
					</Badge>

					{projectRoot && healthStatus === "available" && (
						<span className="max-w-56 truncate text-muted-foreground text-xs">
							{projectRoot}
						</span>
					)}

					{healthStatus === "unavailable" && (
						<Dialog>
							<DialogTrigger asChild>
								<Button size="sm" variant="outline">
									Start agent
								</Button>
							</DialogTrigger>
							<DialogContent>
								<DialogHeader>
									<DialogTitle>Start the local agent</DialogTitle>
									<DialogDescription>
										The Stackpanel agent runs on your machine (localhost) and lets
										this UI manage files and run commands safely in your repo.
									</DialogDescription>
								</DialogHeader>

								<div className="space-y-3 text-sm">
									<ol className="list-decimal space-y-2 pl-4 text-muted-foreground">
										<li>
											Open a terminal in the repo and enter the dev shell (if you
											haven&apos;t):
											<div className="mt-1 rounded-md border border-border bg-secondary/30 p-2 font-mono text-foreground">
												nix develop
											</div>
										</li>
										<li>
											Run the agent:
											<div className="mt-1 flex items-center justify-between gap-2 rounded-md border border-border bg-secondary/30 p-2 font-mono text-foreground">
												<span className="truncate">{startAgentCommand}</span>
												<Button
													className="h-8 w-8"
													onClick={async () => {
														await navigator.clipboard.writeText(startAgentCommand);
														toast.success("Copied");
													}}
													size="icon"
													variant="ghost"
												>
													<Copy className="h-4 w-4" />
												</Button>
											</div>
											<div className="mt-2 rounded-md border border-border bg-secondary/30 p-2 font-mono text-foreground">
												{startAgentCommandAlt}
											</div>
										</li>
										<li>
											Back here, click <span className="text-foreground">Pair agent</span>{" "}
											(and then <span className="text-foreground">Connect</span>).
										</li>
									</ol>
									<p className="text-muted-foreground text-xs">
										Default agent port is <span className="font-mono">9876</span>.
										You can customize via <span className="font-mono">.stackpanel/agent.yaml</span>{" "}
										or flags.
									</p>
								</div>
							</DialogContent>
						</Dialog>
					)}

					{healthStatus === "available" && !token && (
						<Button onClick={pair} size="sm" variant="outline">
							Pair agent
						</Button>
					)}

					{healthStatus === "available" && token && !isConnected && !isConnecting && (
						<Button onClick={connect} size="sm" variant="outline">
							Connect
						</Button>
					)}

					{token && (
						<Button onClick={clearPairing} size="sm" variant="ghost">
							Forget
						</Button>
					)}

					<Button
						className="text-muted-foreground hover:text-foreground"
						size="icon"
						variant="ghost"
					>
						<ExternalLink className="h-4 w-4" />
					</Button>
				</div> */}

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button className="rounded-full" size="icon" variant="ghost">
              <Avatar className="h-8 w-8">
                <AvatarFallback className="bg-accent text-accent-foreground text-sm">
                  JD
                </AvatarFallback>
              </Avatar>
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-48">
            <DropdownMenuItem>
              <User className="mr-2 h-4 w-4" />
              Profile
            </DropdownMenuItem>
            <DropdownMenuItem>
              <Settings className="mr-2 h-4 w-4" />
              Settings
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem className="text-destructive">
              <LogOut className="mr-2 h-4 w-4" />
              Sign out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  );
}
