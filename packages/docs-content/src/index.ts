// Guide imports
import appsGuide from "../content/guides/apps.mdx?raw";
import configurationGuide from "../content/guides/configuration.mdx?raw";
import devshellGuide from "../content/guides/devshell.mdx?raw";
import networkGuide from "../content/guides/network.mdx?raw";
import packagesGuide from "../content/guides/packages.mdx?raw";
import secretsGuide from "../content/guides/secrets.mdx?raw";
import servicesGuide from "../content/guides/services.mdx?raw";
import setupGuide from "../content/guides/setup.mdx?raw";
import tasksGuide from "../content/guides/tasks.mdx?raw";
import teamGuide from "../content/guides/team.mdx?raw";
import variablesGuide from "../content/guides/variables.mdx?raw";

export type GuideEntry = {
	slug: string;
	title: string;
	description?: string;
	content: string;
};

export const guides = {
	apps: {
		slug: "guides/apps",
		title: "Apps",
		description: "Define and manage applications in your monorepo",
		content: appsGuide,
	},
	configuration: {
		slug: "guides/configuration",
		title: "Configuration",
		description: "Project configuration files and structure",
		content: configurationGuide,
	},
	devshell: {
		slug: "guides/devshell",
		title: "Dev Shell",
		description: "Your reproducible development environment",
		content: devshellGuide,
	},
	network: {
		slug: "guides/network",
		title: "Network",
		description: "Local domains, TLS, and reverse proxy with Caddy",
		content: networkGuide,
	},
	packages: {
		slug: "guides/packages",
		title: "Packages",
		description: "Nix packages for reproducible development environments",
		content: packagesGuide,
	},
	secrets: {
		slug: "guides/secrets",
		title: "Secrets",
		description: "Encrypted secrets management with AGE and SOPS",
		content: secretsGuide,
	},
	services: {
		slug: "guides/services",
		title: "Services",
		description: "Background services like databases and caches",
		content: servicesGuide,
	},
	setup: {
		slug: "guides/setup",
		title: "Setup Wizard",
		description: "Complete initial project configuration",
		content: setupGuide,
	},
	tasks: {
		slug: "guides/tasks",
		title: "Tasks",
		description: "Declarative task definitions with Turborepo integration",
		content: tasksGuide,
	},
	team: {
		slug: "guides/team",
		title: "Team",
		description: "Team members and access control",
		content: teamGuide,
	},
	variables: {
		slug: "guides/variables",
		title: "Variables",
		description: "Shared configuration values for your apps",
		content: variablesGuide,
	},
} satisfies Record<string, GuideEntry>;

// Export individual guides for direct imports
export {
	appsGuide,
	configurationGuide,
	devshellGuide,
	networkGuide,
	packagesGuide,
	secretsGuide,
	servicesGuide,
	setupGuide,
	tasksGuide,
	teamGuide,
	variablesGuide,
};
