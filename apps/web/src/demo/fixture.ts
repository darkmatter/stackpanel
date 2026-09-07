/**
 * Frozen fixture data for the demo agent.
 *
 * Mirrors `.stack/state/stack.json` plus the entity tables, Connect-RPC
 * payloads, and REST surfaces the studio reads on first paint. Values follow
 * the examples in nix/stackpanel/modules schema.nix files and
 * nix/stackpanel/db/schemas proto.nix files so the demo looks like a real
 * stackpanel-demo workspace rather than an empty project.
 */

export const DEMO_HOST = "demo-agent.stackpanel.local";
export const DEMO_PORT = 9876;
export const DEMO_BASE_URL = `http://${DEMO_HOST}:${DEMO_PORT}`;

const NOW = "2026-09-03T18:00:00Z";
const PROJECT_ROOT = "/home/demo/stackpanel-demo";
const AGE_DEMO = "age1abc1234abc1234abc1234abc1234abc1234abc1234abc1234abc1";
const AGE_COOPER = "age1def5678def5678def5678def5678def5678def5678def5678def5";

export const demoStateJson = {
	version: 1,
	projectName: "stackpanel-demo",
	basePort: 6400,
	paths: {
		state: ".stack/state",
		gen: ".stack/gen",
		data: ".stack",
		keys: ".stack/keys",
	},
	apps: {
		web: {
			port: 6402,
			domain: "stackpanel-demo.localhost",
			url: "http://stackpanel-demo.localhost",
			tls: false,
		},
		server: {
			port: 6401,
			domain: null,
			url: null,
			tls: false,
		},
		docs: {
			port: 6400,
			domain: "docs.stackpanel-demo.localhost",
			url: "http://docs.stackpanel-demo.localhost",
			tls: false,
		},
	},
	services: {
		postgres: {
			key: "POSTGRES",
			name: "PostgreSQL",
			displayName: "PostgreSQL",
			enable: true,
			port: 6410,
			envVar: "STACKPANEL_POSTGRES_PORT",
		},
		redis: {
			key: "REDIS",
			name: "Redis",
			displayName: "Redis",
			enable: true,
			port: 6411,
			envVar: "STACKPANEL_REDIS_PORT",
		},
		minio: {
			key: "MINIO",
			name: "MinIO",
			displayName: "MinIO",
			enable: true,
			port: 6412,
			envVar: "STACKPANEL_MINIO_PORT",
		},
		caddy: {
			key: "CADDY",
			name: "Caddy",
			displayName: "Caddy",
			enable: true,
			port: 443,
			envVar: "STACKPANEL_CADDY_PORT",
		},
	},
	network: {
		step: { enable: true, caUrl: "https://ca.stackpanel-demo.localhost" },
	},
	stepCa: {
		"step-ca": {
			enable: true,
			"ca-url": "https://ca.stackpanel-demo.localhost",
			"ca-fingerprint": "abc123def456abc123def456abc123def456abc123def456abc123def456",
			provisioner: "admin",
			"cert-name": "demo-workstation",
		},
	},
} as const;

const builtinSource = {
	type: "builtin" as const,
	flakeInput: null,
	path: null,
	registryId: null,
	ref: null,
};

function features(partial: Partial<Record<string, boolean>>) {
	return {
		files: false,
		scripts: false,
		tasks: false,
		healthchecks: false,
		services: false,
		secrets: false,
		packages: false,
		appModule: false,
		...partial,
	};
}

function strField(
	name: string,
	label: string,
	opts: {
		placeholder?: string;
		example?: string;
		description?: string;
		editPath?: string;
		type?: string;
		options?: string[];
	} = {},
) {
	return {
		name,
		type: opts.type ?? "FIELD_TYPE_STRING",
		value: "",
		label,
		editable: true,
		editPath: opts.editPath ?? name,
		placeholder: opts.placeholder ?? opts.example ?? null,
		description: opts.description ?? null,
		example: opts.example ?? null,
		options: opts.options ?? [],
	};
}

const bunAppConfig = {
	mainPackage: ".",
	version: "1.4.2",
	binaryName: "web",
	buildPhase: "bun run build",
	startScript: "bun run start",
	runtimeEnv: JSON.stringify({ NODE_ENV: "production" }),
	inheritPath: "false",
	generateFiles: "true",
	description: "Studio UI on Cloudflare Workers",
	outputDir: ".output",
};

const docsAppConfig = {
	...bunAppConfig,
	binaryName: "docs",
	description: "Documentation site",
	outputDir: "dist",
	buildPhase: "bun run build",
};

const goAppConfig = {
	mainPackage: "./cmd/stackpanel",
	version: "1.25.0",
	binaryName: "stackpanel",
	ldflags: JSON.stringify(["-s", "-w", "-X main.version=1.25.0"]),
	watchDirs: JSON.stringify(["cmd", "internal"]),
	devArgs: JSON.stringify(["serve"]),
	generateFiles: "true",
	description: "Local agent, CLI, and TUI",
};

const oxlintAppConfig = {
	configPath: ".oxlintrc.json",
	plugins: JSON.stringify(["react", "typescript", "import", "jsx-a11y"]),
	categories: JSON.stringify({
		correctness: "error",
		suspicious: "warn",
		pedantic: "off",
		style: "off",
		nursery: "off",
	}),
	rules: JSON.stringify({
		"no-console": "warn",
		"no-debugger": "error",
		eqeqeq: "error",
	}),
	ignorePatterns: JSON.stringify([
		"node_modules",
		"dist",
		"build",
		".output",
		"coverage",
	]),
	paths: JSON.stringify(["src"]),
	fix: "false",
	gitHook: "true",
};

const bunFields = [
	strField("mainPackage", "Main Package", {
		placeholder: "src/index.ts",
		example: "src/index.ts",
		editPath: "bun.mainPackage",
		description: "Main Bun entry point passed to generated package metadata.",
	}),
	strField("version", "Version", {
		placeholder: "1.4.2",
		example: "1.4.2",
		editPath: "bun.version",
	}),
	strField("binaryName", "Binary Name", {
		placeholder: "web",
		example: "web",
		editPath: "bun.binaryName",
	}),
	strField("buildPhase", "Build Phase", {
		placeholder: "bun run build",
		example: "bun run build:web",
		editPath: "bun.buildPhase",
	}),
	strField("startScript", "Start Script", {
		placeholder: "bun run start",
		example: "bun run start",
		editPath: "bun.startScript",
	}),
	strField("runtimeEnv", "Runtime Environment", {
		type: "FIELD_TYPE_JSON",
		example: '{"NODE_ENV":"production"}',
		editPath: "bun.runtimeEnv",
	}),
	strField("inheritPath", "Inherit PATH", {
		type: "FIELD_TYPE_BOOLEAN",
		editPath: "bun.inheritPath",
	}),
	strField("generateFiles", "Generate Files", {
		type: "FIELD_TYPE_BOOLEAN",
		editPath: "bun.generateFiles",
	}),
	strField("description", "Description", {
		placeholder: "Studio UI on Cloudflare Workers",
		example: "Studio UI on Cloudflare Workers",
		editPath: "bun.description",
	}),
	strField("outputDir", "Output Directory", {
		placeholder: ".output",
		example: "dist",
		editPath: "bun.outputDir",
	}),
];

const goFields = [
	strField("mainPackage", "Main Package", {
		placeholder: "./cmd/server",
		example: "./cmd/server",
		editPath: "go.mainPackage",
	}),
	strField("version", "Version", {
		placeholder: "1.25.0",
		example: "1.25.0",
		editPath: "go.version",
	}),
	strField("binaryName", "Binary Name", {
		placeholder: "stackpanel",
		example: "stackpanel",
		editPath: "go.binaryName",
	}),
	strField("ldflags", "Linker Flags", {
		type: "FIELD_TYPE_MULTISELECT",
		example: '["-X main.version=1.0.0"]',
		editPath: "go.ldflags",
	}),
	strField("watchDirs", "Watch Directories", {
		type: "FIELD_TYPE_MULTISELECT",
		editPath: "go.watchDirs",
	}),
	strField("devArgs", "Dev Arguments", {
		type: "FIELD_TYPE_MULTISELECT",
		example: '["serve","--port=3000"]',
		editPath: "go.devArgs",
	}),
	strField("generateFiles", "Generate Files", {
		type: "FIELD_TYPE_BOOLEAN",
		editPath: "go.generateFiles",
	}),
	strField("description", "Description", {
		placeholder: "Local agent, CLI, and TUI",
		example: "Local agent, CLI, and TUI",
		editPath: "go.description",
	}),
];

const oxlintFields = [
	strField("configPath", "Config Path", {
		placeholder: ".oxlintrc.json",
		example: "oxlint.json",
		editPath: "linting.oxlint.configPath",
	}),
	strField("plugins", "Plugins", {
		type: "FIELD_TYPE_MULTISELECT",
		example: '["react","typescript","import","jsx-a11y"]',
		editPath: "linting.oxlint.plugins",
	}),
	strField("categories", "Categories", {
		type: "FIELD_TYPE_CODE",
		editPath: "linting.oxlint.categories",
	}),
	strField("rules", "Rules", {
		type: "FIELD_TYPE_JSON",
		example: '{"no-console":"warn"}',
		editPath: "linting.oxlint.rules",
	}),
	strField("ignorePatterns", "Ignore Patterns", {
		type: "FIELD_TYPE_MULTISELECT",
		editPath: "linting.oxlint.ignorePatterns",
	}),
	strField("paths", "Paths", {
		type: "FIELD_TYPE_MULTISELECT",
		editPath: "linting.oxlint.paths",
	}),
	strField("fix", "Auto Fix", {
		type: "FIELD_TYPE_BOOLEAN",
		editPath: "linting.oxlint.fix",
	}),
	strField("gitHook", "Git Hook", {
		type: "FIELD_TYPE_BOOLEAN",
		editPath: "linting.oxlint.gitHook",
	}),
];

function statusPanel(
	id: string,
	module: string,
	title: string,
	icon: string,
	order: number,
	metrics: Array<{ label: string; value: string; status: "ok" | "warning" | "error" }>,
	description?: string,
) {
	return {
		id,
		module,
		title,
		description: description ?? null,
		icon,
		type: "PANEL_TYPE_STATUS",
		order,
		enabled: true,
		fields: [
			{
				name: "metrics",
				type: "FIELD_TYPE_STRING",
				value: JSON.stringify(metrics),
				label: "Metrics",
				editable: false,
			},
		],
		apps: {},
	};
}

const bunAppsPanel = {
	id: "bun-apps",
	module: "bun",
	title: "Bun Apps",
	description: "TypeScript apps packaged with bun2nix",
	icon: "code",
	type: "PANEL_TYPE_APPS_GRID",
	order: 15,
	enabled: true,
	fields: [
		{
			name: "columns",
			type: "FIELD_TYPE_STRING",
			value: JSON.stringify(["name", "path", "version", "port"]),
			label: "Columns",
			editable: false,
		},
	],
	apps: {
		web: {
			enabled: true,
			config: {
				name: "Studio",
				path: "apps/web",
				version: "1.4.2",
				port: "6402",
			},
		},
		docs: {
			enabled: true,
			config: {
				name: "Docs",
				path: "apps/docs",
				version: "1.4.2",
				port: "6400",
			},
		},
	},
};

const goAppsPanel = {
	id: "go-apps",
	module: "go",
	title: "Go Apps",
	description: "Go binaries packaged with gomod2nix",
	icon: "code",
	type: "PANEL_TYPE_APPS_GRID",
	order: 15,
	enabled: true,
	fields: [
		{
			name: "columns",
			type: "FIELD_TYPE_STRING",
			value: JSON.stringify(["name", "path", "version", "port"]),
			label: "Columns",
			editable: false,
		},
	],
	apps: {
		server: {
			enabled: true,
			config: {
				name: "Agent",
				path: "apps/stackpanel-go",
				version: "1.25.0",
				port: "6401",
			},
		},
	},
};

const bunConfigPanel = {
	id: "bun-config",
	module: "bun",
	title: "Bun Configuration",
	description: "Per-app Bun/TypeScript packaging",
	icon: "code",
	type: "PANEL_TYPE_APP_CONFIG",
	order: 100,
	enabled: true,
	fields: bunFields,
	apps: {
		web: { enabled: true, config: bunAppConfig },
		docs: { enabled: true, config: docsAppConfig },
	},
};

const goConfigPanel = {
	id: "go-config",
	module: "go",
	title: "Go Configuration",
	description: "Per-app Go packaging and Air reload",
	icon: "code",
	type: "PANEL_TYPE_APP_CONFIG",
	order: 100,
	enabled: true,
	fields: goFields,
	apps: {
		server: { enabled: true, config: goAppConfig },
	},
};

const oxlintConfigPanel = {
	id: "oxlint-config",
	module: "oxlint",
	title: "OxLint Configuration",
	description: "JavaScript/TypeScript linting",
	icon: "gauge",
	type: "PANEL_TYPE_APP_CONFIG",
	order: 110,
	enabled: true,
	fields: oxlintFields,
	apps: {
		web: { enabled: true, config: oxlintAppConfig },
		docs: { enabled: true, config: { ...oxlintAppConfig, plugins: JSON.stringify(["typescript"]) } },
	},
};

const containerFields = [
	strField("name", "Image Name", {
		placeholder: "stackpanel-web",
		example: "stackpanel-web",
		editPath: "container.name",
	}),
	strField("version", "Version", {
		placeholder: "latest",
		example: "v1.2.3",
		editPath: "container.version",
	}),
	strField("type", "Type", {
		type: "FIELD_TYPE_SELECT",
		options: ["bun", "node", "go", "static", "custom"],
		editPath: "container.type",
	}),
	strField("port", "Port", {
		type: "FIELD_TYPE_NUMBER",
		placeholder: "3000",
		example: "6402",
		editPath: "container.port",
	}),
	strField("registry", "Registry", {
		placeholder: "docker://registry.fly.io/",
		example: "docker://registry.fly.io/stackpanel-demo",
		editPath: "container.registry",
	}),
	strField("workingDir", "Working Directory", {
		placeholder: "/app",
		example: "/app",
		editPath: "container.workingDir",
	}),
	strField("buildOutputPath", "Build Output Path", {
		placeholder: "apps/web/.output",
		example: "apps/web/.output",
		editPath: "container.buildOutputPath",
	}),
	strField("maxLayers", "Max Layers", {
		type: "FIELD_TYPE_NUMBER",
		placeholder: "100",
		example: "50",
		editPath: "container.maxLayers",
	}),
];

const containerConfigPanel = {
	id: "container-config",
	module: "containers",
	title: "Container Configuration",
	description: "OCI image packaging with nix2container",
	icon: "box",
	type: "PANEL_TYPE_APP_CONFIG",
	order: 120,
	enabled: true,
	fields: containerFields,
	apps: {
		web: {
			enabled: true,
			config: {
				name: "stackpanel-web",
				version: "1.4.2",
				type: "bun",
				port: "6402",
				registry: "docker://registry.fly.io/stackpanel-demo",
				workingDir: "/app",
				buildOutputPath: "apps/web/.output",
				maxLayers: "100",
			},
		},
		server: {
			enabled: true,
			config: {
				name: "stackpanel-agent",
				version: "1.25.0",
				type: "go",
				port: "6401",
				registry: "docker://registry.fly.io/stackpanel-demo",
				workingDir: "/app",
				buildOutputPath: "apps/stackpanel-go",
				maxLayers: "50",
			},
		},
	},
};

const cloudflareFields = [
	strField("workerName", "Worker Name", {
		placeholder: "stackpanel-studio",
		example: "stackpanel-studio",
		editPath: "deployment.cloudflare.workerName",
	}),
	strField("route", "Route", {
		placeholder: "stackpanel-demo.localhost/*",
		example: "stackpanel-demo.localhost/*",
		editPath: "deployment.cloudflare.route",
	}),
	strField("compatibility", "Compatibility", {
		type: "FIELD_TYPE_SELECT",
		options: ["node", "browser"],
		editPath: "deployment.cloudflare.compatibility",
	}),
];

const cloudflareConfigPanel = {
	id: "cloudflare-config",
	module: "deployment-cloudflare",
	title: "Cloudflare Workers",
	description: "Worker name, route, and compatibility",
	icon: "cloud",
	type: "PANEL_TYPE_APP_CONFIG",
	order: 130,
	enabled: true,
	fields: cloudflareFields,
	apps: {
		web: {
			enabled: true,
			config: {
				workerName: "stackpanel-studio",
				route: "stackpanel-demo.localhost/*",
				compatibility: "node",
			},
		},
		docs: {
			enabled: true,
			config: {
				workerName: "stackpanel-docs",
				route: "docs.stackpanel-demo.localhost/*",
				compatibility: "node",
			},
		},
	},
};

const flyFields = [
	strField("appName", "App Name", {
		placeholder: "stackpanel-studio",
		example: "stackpanel-studio",
		editPath: "deployment.fly.appName",
	}),
	strField("region", "Region", {
		type: "FIELD_TYPE_SELECT",
		options: ["iad", "lax", "ord", "lhr", "ams"],
		editPath: "deployment.fly.region",
	}),
	strField("memory", "Memory", {
		type: "FIELD_TYPE_SELECT",
		options: ["256mb", "512mb", "1gb", "2gb"],
		editPath: "deployment.fly.memory",
	}),
	strField("cpuKind", "CPU Type", {
		type: "FIELD_TYPE_SELECT",
		options: ["shared", "performance"],
		editPath: "deployment.fly.cpuKind",
	}),
	strField("cpus", "CPUs", {
		type: "FIELD_TYPE_NUMBER",
		placeholder: "1",
		example: "2",
		editPath: "deployment.fly.cpus",
	}),
	strField("autoStop", "Auto Stop", {
		type: "FIELD_TYPE_SELECT",
		options: ["off", "stop", "suspend"],
		editPath: "deployment.fly.autoStop",
	}),
];

const flyConfigPanel = {
	id: "fly-config",
	module: "deployment-fly",
	title: "Fly.io",
	description: "Machine size, region, and auto-stop",
	icon: "rocket",
	type: "PANEL_TYPE_APP_CONFIG",
	order: 131,
	enabled: true,
	fields: flyFields,
	apps: {
		server: {
			enabled: true,
			config: {
				appName: "stackpanel-agent",
				region: "iad",
				memory: "512mb",
				cpuKind: "shared",
				cpus: "1",
				autoStop: "suspend",
			},
		},
	},
};

const dashboardPanels = {
	"postgres-status": statusPanel(
		"postgres-status",
		"postgres",
		"PostgreSQL",
		"server",
		10,
		[
			{ label: "Status", value: "listening", status: "ok" },
			{ label: "Port", value: "6410", status: "ok" },
			{ label: "Version", value: "16", status: "ok" },
			{ label: "Databases", value: "stackpanel", status: "ok" },
		],
		"Managed PostgreSQL for local development",
	),
	"redis-status": statusPanel(
		"redis-status",
		"redis",
		"Redis",
		"server",
		20,
		[
			{ label: "Status", value: "ready", status: "ok" },
			{ label: "Port", value: "6411", status: "ok" },
			{ label: "Max memory", value: "256mb", status: "ok" },
		],
	),
	"caddy-status": statusPanel(
		"caddy-status",
		"caddy",
		"Reverse Proxy",
		"network",
		30,
		[
			{ label: "Status", value: "serving", status: "ok" },
			{ label: "Sites", value: "2", status: "ok" },
			{ label: "TLS", value: "off (dev)", status: "ok" },
		],
		"Caddy sites for stackpanel-demo.localhost",
	),
	"go-status": statusPanel(
		"go-status",
		"go",
		"Go Environment",
		"code",
		10,
		[
			{ label: "Go Version", value: "1.25.0", status: "ok" },
			{ label: "Apps", value: "1", status: "ok" },
			{ label: "Air", value: "watching", status: "ok" },
		],
	),
	"bun-status": statusPanel(
		"bun-status",
		"bun",
		"Bun Environment",
		"code",
		10,
		[
			{ label: "Bun Version", value: "1.2.4", status: "ok" },
			{ label: "Apps", value: "2", status: "ok" },
			{ label: "Lockfile", value: "bun.lock", status: "ok" },
		],
	),
	"healthchecks-status": statusPanel(
		"healthchecks-status",
		"healthchecks",
		"Healthchecks",
		"activity",
		5,
		[
			{ label: "Overall", value: "healthy", status: "ok" },
			{ label: "Passing", value: "8 / 8", status: "ok" },
			{ label: "Last run", value: "just now", status: "ok" },
		],
	),
	"bun-apps": bunAppsPanel,
	"go-apps": goAppsPanel,
};

const allPanels = {
	...dashboardPanels,
	"bun-config": bunConfigPanel,
	"go-config": goConfigPanel,
	"oxlint-config": oxlintConfigPanel,
	"container-config": containerConfigPanel,
	"cloudflare-config": cloudflareConfigPanel,
	"fly-config": flyConfigPanel,
};

export const demoNixConfig = {
	version: 1,
	name: "stackpanel-demo",
	projectName: "stackpanel-demo",
	projectRoot: PROJECT_ROOT,
	github: "darkmatter/stackpanel",
	basePort: demoStateJson.basePort,
	processComposePort: 6490,
	paths: demoStateJson.paths,
	apps: demoStateJson.apps,
	services: demoStateJson.services,
	network: demoStateJson.network,
	stepCa: demoStateJson.stepCa,
	theme: { palette: "tokyo-night" },
	packages: [
		{ name: "bun", version: "1.2.4", attrPath: "bun", source: "devshell" },
		{ name: "go", version: "1.25.0", attrPath: "go", source: "devshell" },
		{
			name: "postgresql",
			version: "16.4",
			attrPath: "postgresql_16",
			source: "devshell",
		},
		{ name: "redis", version: "7.4.1", attrPath: "redis", source: "devshell" },
		{ name: "caddy", version: "2.9.1", attrPath: "caddy", source: "devshell" },
		{ name: "air", version: "1.61.7", attrPath: "air", source: "devshell" },
		{ name: "oxlint", version: "0.16.0", attrPath: "oxlint", source: "user" },
	],
	healthchecks: [
		{
			id: "postgres-port",
			name: "PostgreSQL listening",
			description: "Verifies PostgreSQL is accepting connections",
			module: "postgres",
			tags: ["database"],
			enabled: true,
			type: "HEALTHCHECK_TYPE_TCP",
			severity: "HEALTHCHECK_SEVERITY_CRITICAL",
			tcpHost: "localhost",
			tcpPort: 6410,
			timeout: 10,
		},
		{
			id: "redis-port",
			name: "Redis listening",
			description: "Verifies Redis is accepting connections",
			module: "redis",
			tags: ["cache"],
			enabled: true,
			type: "HEALTHCHECK_TYPE_TCP",
			severity: "HEALTHCHECK_SEVERITY_CRITICAL",
			tcpHost: "localhost",
			tcpPort: 6411,
			timeout: 10,
		},
		{
			id: "web-http",
			name: "Studio HTTP",
			description: "Studio UI responds on its assigned port",
			module: "bun",
			tags: ["web"],
			enabled: true,
			type: "HEALTHCHECK_TYPE_HTTP",
			severity: "HEALTHCHECK_SEVERITY_WARNING",
			httpUrl: "http://stackpanel-demo.localhost",
			httpMethod: "GET",
			httpExpectedStatus: 200,
			timeout: 10,
		},
	],
	panels: dashboardPanels,
	panelModules: ["healthchecks", "postgres", "redis", "caddy", "bun", "go"],
	panelsComputed: allPanels,
	ui: {
		panels: allPanels,
		panelModules: [
			"healthchecks",
			"postgres",
			"redis",
			"caddy",
			"bun",
			"go",
			"oxlint",
		],
		modules: {},
		modulesList: ["bun", "go", "oxlint", "process-compose", "turbo", "git-hooks"],
	},
	users: {
		"demo-user": {
			name: "Demo User",
			email: "demo@stackpanel.com",
			github: "stackpanel-demo",
		},
		cooper: {
			name: "Cooper Davis",
			email: "cooper@darkmatter.io",
			github: "cooperdavis",
		},
	},
	secrets: {
		enable: true,
		inputDirectory: ".stack/secrets",
		secretsDir: ".stack/secrets",
		environments: {
			dev: { name: "dev", sources: ["dev", "shared"] },
			staging: { name: "staging", sources: ["staging"] },
		},
		codegen: {
			typescript: {
				name: "env",
				directory: "packages/gen/env/src",
				language: "typescript",
			},
		},
	},
	missingFlakeInputs: [],
	moduleRequirements: {},
	motd: { enable: true, commands: [], features: [], hints: [] },
};

export const demoAppsRpc = {
	web: {
		name: "Studio",
		description: "Stackpanel Studio web UI",
		path: "apps/web",
		type: "bun",
		port: 6402,
		domain: "stackpanel-demo.localhost",
		environmentIds: ["dev", "staging", "prod", "test"],
		environments: {},
		env: {
			DATABASE_URL: {
				key: "DATABASE_URL",
				required: true,
				secret: true,
				sops: "/dev/DATABASE_URL",
				value: "ref+sops://.stack/secrets/vars/dev.sops.yaml#/DATABASE_URL",
			},
			API_BASE_URL: {
				key: "API_BASE_URL",
				required: false,
				secret: false,
				value: "https://api.stackpanel-demo.localhost",
			},
			PORT: {
				key: "PORT",
				required: false,
				secret: false,
				value: "6402",
			},
		},
	},
	server: {
		name: "Agent",
		description: "Local Go agent and CLI",
		path: "apps/stackpanel-go",
		type: "go",
		port: 6401,
		environmentIds: ["dev", "staging", "prod", "test"],
		environments: {},
		env: {
			DATABASE_URL: {
				key: "DATABASE_URL",
				required: true,
				secret: true,
				sops: "/dev/DATABASE_URL",
				value: "ref+sops://.stack/secrets/vars/dev.sops.yaml#/DATABASE_URL",
			},
			REDIS_URL: {
				key: "REDIS_URL",
				required: false,
				secret: false,
				value: "redis://localhost:6411",
			},
		},
	},
	docs: {
		name: "Docs",
		description: "Documentation site",
		path: "apps/docs",
		type: "bun",
		port: 6400,
		domain: "docs.stackpanel-demo.localhost",
		environmentIds: ["dev"],
		environments: {},
		env: {
			API_BASE_URL: {
				key: "API_BASE_URL",
				required: false,
				secret: false,
				value: "https://api.stackpanel-demo.localhost",
			},
		},
	},
};

export const demoUsersRpc = {
	"demo-user": {
		name: "Demo User",
		github: "stackpanel-demo",
		email: "demo@stackpanel.com",
		publicKeys: [AGE_DEMO],
		secretsAllowedEnvironments: ["dev"],
	},
	cooper: {
		name: "Cooper Davis",
		github: "cooperdavis",
		email: "cooper@darkmatter.io",
		publicKeys: [AGE_COOPER],
		secretsAllowedEnvironments: ["dev", "staging", "prod"],
	},
};

export const demoVariablesRpc = {
	"/dev/DATABASE_URL": {
		id: "/dev/DATABASE_URL",
		value: "ref+sops://.stack/secrets/vars/dev.sops.yaml#/DATABASE_URL",
	},
	"/dev/REDIS_URL": {
		id: "/dev/REDIS_URL",
		value: "ref+sops://.stack/secrets/vars/dev.sops.yaml#/REDIS_URL",
	},
	"/var/API_BASE_URL": {
		id: "/var/API_BASE_URL",
		value: "https://api.stackpanel-demo.localhost",
	},
	"/var/LOG_LEVEL": {
		id: "/var/LOG_LEVEL",
		value: "info",
	},
	"/var/NODE_ENV": {
		id: "/var/NODE_ENV",
		value: "development",
	},
	"/computed/apps/web/port": {
		id: "/computed/apps/web/port",
		value: "6402",
	},
	"/computed/services/postgres/port": {
		id: "/computed/services/postgres/port",
		value: "6410",
	},
	"/computed/services/redis/port": {
		id: "/computed/services/redis/port",
		value: "6411",
	},
};

export const demoSecretsRpc = {
	enable: true,
	masterKeys: {
		local: {
			agePub: AGE_DEMO,
			ref: "ref+file://.stack/keys/local.txt",
		},
	},
	inputDirectory: ".stack/secrets",
	secretsDir: ".stack/secrets",
	systemKeys: [],
	environments: {
		dev: {
			name: "dev",
			sources: ["dev", "shared"],
			publicKeys: [AGE_DEMO, AGE_COOPER],
		},
		staging: {
			name: "staging",
			sources: ["staging"],
			publicKeys: [AGE_COOPER],
		},
	},
	codegen: {
		typescript: {
			name: "env",
			directory: "packages/gen/env/src",
			language: "typescript",
		},
	},
};

export const demoConfigRpc = {
	enable: true,
	name: "stackpanel-demo",
	github: "darkmatter/stackpanel",
	debug: false,
};

export const demoEntities: Record<string, Record<string, unknown> | unknown> = {
	apps: {
		web: {
			name: "Studio",
			path: "apps/web",
			type: "bun",
			port: 6402,
			domain: "stackpanel-demo.localhost",
		},
		server: {
			name: "Agent",
			path: "apps/stackpanel-go",
			type: "go",
			port: 6401,
		},
		docs: {
			name: "Docs",
			path: "apps/docs",
			type: "bun",
			port: 6400,
			domain: "docs.stackpanel-demo.localhost",
		},
	},
	services: demoStateJson.services as Record<string, unknown>,
	users: {
		"demo-user": {
			name: "Demo User",
			email: "demo@stackpanel.com",
			github: "stackpanel-demo",
			"public-keys": [AGE_DEMO],
			"secrets-allowed-environments": ["dev"],
		},
		cooper: {
			name: "Cooper Davis",
			email: "cooper@darkmatter.io",
			github: "cooperdavis",
			"public-keys": [AGE_COOPER],
			"secrets-allowed-environments": ["dev", "staging", "prod"],
		},
	},
	variables: demoVariablesRpc,
	tasks: {
		build: {
			exec: "bun run build",
			description: "Build all packages",
			"depends-on": ["^build"],
			outputs: ["dist/**"],
		},
		dev: {
			description: "Start development servers",
			persistent: true,
			cache: false,
		},
		test: {
			exec: "bun run test",
			description: "Run unit tests",
			"depends-on": ["build"],
			outputs: ["coverage/**"],
		},
		lint: {
			exec: "bun run lint",
			description: "Lint the workspace",
		},
	},
	packages: ["bun", "go", "postgresql_16", "redis", "caddy", "air", "oxlint"],
	secrets: {
		recipients: {
			"demo-user": {
				"public-key": AGE_DEMO,
				tags: ["dev"],
			},
			cooper: {
				"public-key": AGE_COOPER,
				tags: ["dev", "staging", "prod"],
			},
		},
		"recipient-groups": {
			developers: { recipients: ["demo-user", "cooper"] },
			prod: { recipients: ["cooper"] },
		},
		"creation-rules": [
			{
				"path-regex": "\\.stack/secrets/vars/dev\\.sops\\.yaml$",
				"recipient-groups": ["developers"],
			},
			{
				"path-regex": "\\.stack/secrets/vars/prod\\.sops\\.yaml$",
				"recipient-groups": ["prod"],
			},
		],
	},
	dns: {
		"default-ttl": 300,
		zones: {
			"stackpanel-demo": {
				domain: "stackpanel-demo.localhost",
				managed: true,
				records: [
					{
						type: "A",
						name: "@",
						value: "127.0.0.1",
						comment: "Studio UI",
					},
					{
						type: "A",
						name: "docs",
						value: "127.0.0.1",
						comment: "Docs site",
					},
					{
						type: "A",
						name: "ca",
						value: "127.0.0.1",
						comment: "Step CA",
					},
				],
			},
		},
	},
	"step-ca": {
		enable: true,
		"ca-url": "https://ca.stackpanel-demo.localhost",
		"ca-fingerprint":
			"abc123def456abc123def456abc123def456abc123def456abc123def456",
		provisioner: "admin",
		"cert-name": "demo-workstation",
		"prompt-on-shell": true,
	},
	infra: {
		machines: {
			enable: true,
			source: "static",
			machines: {
				"demo-dev": {
					name: "demo-dev",
					host: "demo-dev.stackpanel-demo.localhost",
					ssh: { user: "ubuntu", port: 22, key_path: "~/.ssh/id_ed25519" },
					tags: ["dev"],
					roles: ["web", "agent"],
					provider: "local",
					arch: "x86_64-linux",
					public_ip: "127.0.0.1",
					private_ip: "127.0.0.1",
					target_env: "dev",
					labels: { project: "stackpanel-demo" },
					nixos_profile: null,
					nixos_modules: [],
					env: {},
					metadata: {},
				},
			},
		},
	},
	databases: {
		default: "primary",
		databases: {
			primary: {
				type: "postgresql",
				"migrations-path": "./apps/stackpanel-go/migrations",
				"seeds-path": "./apps/stackpanel-go/seeds",
				"auto-migrate": true,
			},
		},
	},
	"generated-files": {
		".stack/gen/ide/vscode/settings.json": {
			path: ".stack/gen/ide/vscode/settings.json",
			enable: true,
			mode: "0644",
			source: "stackpanel.ide.vscode",
			description: "VS Code workspace settings generated by the IDE module",
		},
		"turbo.json": {
			path: "turbo.json",
			enable: true,
			source: "stackpanel.turbo",
			description: "Turborepo pipeline generated from stackpanel.tasks",
		},
	},
	"external-github-collaborators": {
		_meta: { source: "github", generatedAt: NOW },
		collaborators: {
			jamie: {
				login: "jamie-demo",
				role: "admin",
				isAdmin: true,
				publicKeys: [],
			},
		},
	},
};

export const demoHealth = {
	status: "ok",
	projectRoot: PROJECT_ROOT,
	hasProject: true,
	agentId: "demo-agent",
	version: "demo",
};

export const demoProject = {
	id: "demo",
	name: "stackpanel-demo",
	path: PROJECT_ROOT,
	active: true,
	is_default: true,
	last_opened: NOW,
} as const;

export const demoRpcProject = {
	path: PROJECT_ROOT,
	name: "stackpanel-demo",
	github: "darkmatter/stackpanel",
	dirs: {
		home: ".stack",
		state: ".stack/state",
		keys: ".stack/keys",
		gen: ".stack/gen",
	},
};

const processSnapshot = [
	{
		name: "web",
		namespace: "default",
		status: "Running",
		pid: 12_345,
		exitCode: 0,
		isRunning: true,
		restarts: 0,
		systemTime: "30m",
		age_ms: 1_800_000,
	},
	{
		name: "server",
		namespace: "default",
		status: "Running",
		pid: 12_346,
		exitCode: 0,
		isRunning: true,
		restarts: 0,
		systemTime: "30m",
		age_ms: 1_800_000,
	},
	{
		name: "docs",
		namespace: "default",
		status: "Running",
		pid: 12_349,
		exitCode: 0,
		isRunning: true,
		restarts: 0,
		systemTime: "12m",
		age_ms: 720_000,
	},
	{
		name: "postgres",
		namespace: "services",
		status: "Running",
		pid: 12_347,
		exitCode: 0,
		isRunning: true,
		restarts: 0,
		systemTime: "1h",
		age_ms: 3_600_000,
	},
	{
		name: "redis",
		namespace: "services",
		status: "Running",
		pid: 12_348,
		exitCode: 0,
		isRunning: true,
		restarts: 0,
		systemTime: "1h",
		age_ms: 3_600_000,
	},
	{
		name: "minio",
		namespace: "services",
		status: "Running",
		pid: 12_350,
		exitCode: 0,
		isRunning: true,
		restarts: 0,
		systemTime: "1h",
		age_ms: 3_600_000,
	},
	{
		name: "caddy",
		namespace: "services",
		status: "Running",
		pid: 12_351,
		exitCode: 0,
		isRunning: true,
		restarts: 0,
		systemTime: "1h",
		age_ms: 3_600_000,
	},
];

export const demoProcessesRpc = {
	available: true,
	running: true,
	processes: processSnapshot,
	error: "",
};

/** REST process-compose snapshot (snake_case + wrapper fields). */
export const demoProcessComposeProcesses = {
	available: true,
	running: true,
	processes: processSnapshot.map((p) => ({
		name: p.name,
		namespace: p.namespace,
		status: p.status,
		is_running: p.isRunning,
		restarts: p.restarts,
		pid: p.pid,
		age_ms: p.age_ms,
		exit_code: p.exitCode,
		system_time: p.systemTime,
	})),
};

export const demoProcessComposeState = {
	available: true,
	state: {
		projectName: "stackpanel-demo",
		version: "1.40.0",
		numRunning: processSnapshot.length,
		numProcesses: processSnapshot.length,
		memoryUsed: "412MB",
	},
};

export const demoInstalledPackages = {
	packages: demoNixConfig.packages.map((p) => ({
		name: p.name,
		version: p.version,
		attrPath: p.attrPath,
		source: p.source,
	})),
	count: demoNixConfig.packages.length,
};

function check(
	id: string,
	name: string,
	module: string,
	message: string,
	opts: { type?: string; severity?: string; tcpPort?: number; httpUrl?: string } = {},
) {
	return {
		checkId: id,
		status: "HEALTH_STATUS_HEALTHY" as const,
		message,
		durationMs: 12,
		timestamp: NOW,
		check: {
			id,
			name,
			description: message,
			type: opts.type ?? "HEALTHCHECK_TYPE_TCP",
			severity: opts.severity ?? "HEALTHCHECK_SEVERITY_CRITICAL",
			timeout: 10,
			module,
			tags: [module],
			enabled: true,
			tcpHost: opts.httpUrl ? undefined : "localhost",
			tcpPort: opts.tcpPort,
			httpUrl: opts.httpUrl,
			httpMethod: opts.httpUrl ? "GET" : undefined,
			httpExpectedStatus: opts.httpUrl ? 200 : undefined,
		},
	};
}

export const demoHealthSummary = {
	overallStatus: "HEALTH_STATUS_HEALTHY" as const,
	modules: {
		postgres: {
			module: "postgres",
			displayName: "PostgreSQL",
			status: "HEALTH_STATUS_HEALTHY" as const,
			checks: [
				check("postgres-port", "PostgreSQL listening", "postgres", "connected on :6410", {
					tcpPort: 6410,
				}),
				check("postgres-ready", "PostgreSQL ready", "postgres", "SELECT 1 ok", {
					type: "HEALTHCHECK_TYPE_SCRIPT",
				}),
			],
			healthyCount: 2,
			totalCount: 2,
			lastUpdated: NOW,
		},
		redis: {
			module: "redis",
			displayName: "Redis",
			status: "HEALTH_STATUS_HEALTHY" as const,
			checks: [
				check("redis-port", "Redis listening", "redis", "PONG on :6411", {
					tcpPort: 6411,
				}),
			],
			healthyCount: 1,
			totalCount: 1,
			lastUpdated: NOW,
		},
		bun: {
			module: "bun",
			displayName: "Bun",
			status: "HEALTH_STATUS_HEALTHY" as const,
			checks: [
				check("web-http", "Studio HTTP", "bun", "200 from stackpanel-demo.localhost", {
					type: "HEALTHCHECK_TYPE_HTTP",
					severity: "HEALTHCHECK_SEVERITY_WARNING",
					httpUrl: "http://stackpanel-demo.localhost",
				}),
				check("docs-http", "Docs HTTP", "bun", "200 from docs.stackpanel-demo.localhost", {
					type: "HEALTHCHECK_TYPE_HTTP",
					severity: "HEALTHCHECK_SEVERITY_WARNING",
					httpUrl: "http://docs.stackpanel-demo.localhost",
				}),
			],
			healthyCount: 2,
			totalCount: 2,
			lastUpdated: NOW,
		},
		go: {
			module: "go",
			displayName: "Go",
			status: "HEALTH_STATUS_HEALTHY" as const,
			checks: [
				check("agent-http", "Agent health", "go", "agent /health ok", {
					type: "HEALTHCHECK_TYPE_HTTP",
					httpUrl: "http://localhost:6401/health",
				}),
			],
			healthyCount: 1,
			totalCount: 1,
			lastUpdated: NOW,
		},
		caddy: {
			module: "caddy",
			displayName: "Caddy",
			status: "HEALTH_STATUS_HEALTHY" as const,
			checks: [
				check("caddy-admin", "Caddy admin API", "caddy", "admin API reachable", {
					type: "HEALTHCHECK_TYPE_HTTP",
					httpUrl: "http://localhost:2019/config/",
				}),
			],
			healthyCount: 1,
			totalCount: 1,
			lastUpdated: NOW,
		},
		oxlint: {
			module: "oxlint",
			displayName: "OxLint",
			status: "HEALTH_STATUS_HEALTHY" as const,
			checks: [
				check("oxlint-bin", "OxLint binary", "oxlint", "oxlint --version ok", {
					type: "HEALTHCHECK_TYPE_SCRIPT",
					severity: "HEALTHCHECK_SEVERITY_INFO",
				}),
			],
			healthyCount: 1,
			totalCount: 1,
			lastUpdated: NOW,
		},
	},
	totalHealthy: 8,
	totalChecks: 8,
	lastUpdated: NOW,
};

export const demoRestModules = [
	{
		id: "bun",
		enabled: true,
		meta: {
			name: "Bun",
			description: "Bun/TypeScript application support with bun2nix packaging",
			icon: "zap",
			category: "language",
			author: "Stackpanel",
			version: "1.0.0",
			homepage: "https://bun.sh",
		},
		source: builtinSource,
		features: features({
			files: true,
			scripts: true,
			healthchecks: true,
			packages: true,
			appModule: true,
		}),
		requires: [],
		conflicts: [],
		priority: 20,
		tags: ["bun", "typescript", "javascript"],
		healthcheckModule: "bun",
		health: demoHealthSummary.modules.bun,
	},
	{
		id: "go",
		enabled: true,
		meta: {
			name: "Go",
			description: "Go application support with gomod2nix packaging",
			icon: "code",
			category: "language",
			author: "Stackpanel",
			version: "1.0.0",
			homepage: "https://go.dev",
		},
		source: builtinSource,
		features: features({
			files: true,
			scripts: true,
			healthchecks: true,
			packages: true,
			appModule: true,
		}),
		requires: [],
		conflicts: [],
		priority: 20,
		tags: ["go", "golang"],
		healthcheckModule: "go",
		health: demoHealthSummary.modules.go,
	},
	{
		id: "oxlint",
		enabled: true,
		meta: {
			name: "OxLint",
			description: "Blazing fast JavaScript/TypeScript linter written in Rust",
			icon: "search-code",
			category: "development",
			author: "Stackpanel",
			version: "1.0.0",
			homepage: "https://oxc.rs",
		},
		source: builtinSource,
		features: features({
			files: true,
			scripts: true,
			healthchecks: true,
			packages: true,
			appModule: true,
		}),
		requires: [],
		conflicts: [],
		priority: 50,
		tags: ["linting", "javascript", "typescript"],
		healthcheckModule: "oxlint",
		health: demoHealthSummary.modules.oxlint,
	},
	{
		id: "process-compose",
		enabled: true,
		meta: {
			name: "Process Compose",
			description: "Process orchestration with auto-generated app processes",
			icon: "layers",
			category: "development",
			author: "Stackpanel",
			version: "1.0.0",
			homepage: "https://f1bonacc1.github.io/process-compose/",
		},
		source: builtinSource,
		features: features({ scripts: true, packages: true, appModule: true }),
		requires: [],
		conflicts: [],
		priority: 25,
		tags: ["process-compose", "processes", "dev"],
	},
	{
		id: "turbo",
		enabled: true,
		meta: {
			name: "Turborepo",
			description: "Turborepo task orchestration with turbo.json generation",
			icon: "rocket",
			category: "development",
			author: "Stackpanel",
			version: "1.0.0",
			homepage: "https://turbo.build/repo",
		},
		source: builtinSource,
		features: features({ files: true, packages: true, tasks: true, appModule: true }),
		requires: [],
		conflicts: [],
		priority: 15,
		tags: ["turbo", "monorepo", "tasks"],
	},
	{
		id: "git-hooks",
		enabled: true,
		meta: {
			name: "Git Hooks",
			description: "Git hooks integration with pre-commit linters and formatters",
			icon: "git-branch",
			category: "development",
			author: "Stackpanel",
			version: "1.0.0",
			homepage: null,
		},
		source: builtinSource,
		features: features({}),
		requires: [],
		conflicts: [],
		priority: 80,
		tags: ["git", "hooks", "pre-commit"],
	},
	{
		id: "postgres",
		enabled: true,
		meta: {
			name: "PostgreSQL",
			description: "Managed PostgreSQL service for local development",
			icon: "database",
			category: "database",
			author: "Stackpanel",
			version: "1.0.0",
			homepage: "https://www.postgresql.org",
		},
		source: builtinSource,
		features: features({ services: true, healthchecks: true, secrets: true }),
		requires: [],
		conflicts: [],
		priority: 30,
		tags: ["database", "postgres"],
		healthcheckModule: "postgres",
		health: demoHealthSummary.modules.postgres,
	},
	{
		id: "redis",
		enabled: true,
		meta: {
			name: "Redis",
			description: "In-memory cache and queue for local development",
			icon: "database",
			category: "database",
			author: "Stackpanel",
			version: "1.0.0",
			homepage: "https://redis.io",
		},
		source: builtinSource,
		features: features({ services: true, healthchecks: true }),
		requires: [],
		conflicts: [],
		priority: 40,
		tags: ["database", "redis", "cache"],
		healthcheckModule: "redis",
		health: demoHealthSummary.modules.redis,
	},
	{
		id: "caddy",
		enabled: true,
		meta: {
			name: "Caddy",
			description: "Local reverse proxy with automatic .localhost routing",
			icon: "network",
			category: "service",
			author: "Stackpanel",
			version: "1.0.0",
			homepage: "https://caddyserver.com",
		},
		source: builtinSource,
		features: features({ services: true, healthchecks: true, files: true }),
		requires: [],
		conflicts: [],
		priority: 35,
		tags: ["caddy", "proxy", "tls"],
		healthcheckModule: "caddy",
		health: demoHealthSummary.modules.caddy,
	},
];

/** Connect-RPC modules use `enable` and proto enum category names. */
export const demoRpcModules: Record<string, Record<string, unknown>> = Object.fromEntries(
	demoRestModules.map((mod) => [
		mod.id,
		{
			id: mod.id,
			enable: mod.enabled,
			meta: {
				...mod.meta,
				category: `MODULE_CATEGORY_${mod.meta.category.toUpperCase().replace("-", "_")}`,
			},
			source: { type: "MODULE_SOURCE_TYPE_BUILTIN" },
			features: mod.features,
			requires: mod.requires,
			conflicts: mod.conflicts,
			priority: mod.priority,
			tags: mod.tags,
			settings: {},
			panels: [],
			apps: {},
			healthcheckModule: mod.healthcheckModule,
		},
	]),
);

export const demoRegistryModules = {
	modules: [
		{
			id: "postgres-ha",
			meta: {
				name: "PostgreSQL HA",
				description: "High-availability PostgreSQL with streaming replicas",
				category: "database",
				author: "Stackpanel",
				version: "1.2.0",
			},
			features: features({ services: true, healthchecks: true, secrets: true }),
			tags: ["database", "postgres", "ha", "production"],
			flakeUrl: "github:stackpanel/modules",
			flakePath: "stackpanelModules.postgres-ha",
			downloads: 1250,
			rating: 4.8,
			updatedAt: "2024-01-15T10:00:00Z",
			installed: false,
			builtin: false,
		},
		{
			id: "redis-cluster",
			meta: {
				name: "Redis Cluster",
				description: "Sharded Redis cluster for production-like caching",
				category: "database",
				author: "Stackpanel",
				version: "1.0.0",
			},
			features: features({ services: true, healthchecks: true }),
			tags: ["database", "redis", "cache", "cluster"],
			flakeUrl: "github:stackpanel/modules",
			flakePath: "stackpanelModules.redis-cluster",
			downloads: 890,
			rating: 4.5,
			updatedAt: "2024-01-10T10:00:00Z",
			installed: false,
			builtin: false,
		},
		{
			id: "turbo",
			meta: {
				name: "Turborepo",
				description: "Turborepo task orchestration with turbo.json generation",
				category: "development",
				author: "Stackpanel",
				version: "1.0.0",
			},
			features: features({ files: true, packages: true, tasks: true, appModule: true }),
			tags: ["turbo", "monorepo"],
			flakeUrl: "builtin",
			flakePath: "stackpanelModules.turbo",
			downloads: 4200,
			rating: 5,
			updatedAt: NOW,
			installed: true,
			builtin: true,
		},
		{
			id: "git-hooks",
			meta: {
				name: "Git Hooks",
				description: "Git hooks integration with pre-commit linters",
				category: "development",
				author: "Stackpanel",
				version: "1.0.0",
			},
			features: features({}),
			tags: ["git", "hooks"],
			flakeUrl: "builtin",
			flakePath: "stackpanelModules.git-hooks",
			downloads: 2100,
			rating: 4.6,
			updatedAt: NOW,
			installed: true,
			builtin: true,
		},
	],
	total: 4,
	sources: [
		{
			id: "official",
			name: "Stackpanel Registry",
			url: "https://raw.githubusercontent.com/darkmatter/stackpanel-registry/main/modules.json",
			official: true,
			enabled: true,
		},
	],
	lastUpdated: NOW,
};

export const demoTurboQueryResult = {
	data: {
		packageGraph: {
			nodes: {
				items: [
					{
						name: "web",
						path: "apps/web",
						tasks: {
							items: [
								{ name: "dev" },
								{ name: "build" },
								{ name: "lint" },
								{ name: "check-types" },
								{ name: "test" },
							],
						},
					},
					{
						name: "server",
						path: "apps/stackpanel-go",
						tasks: {
							items: [{ name: "dev" }, { name: "build" }, { name: "test" }, { name: "lint" }],
						},
					},
					{
						name: "docs",
						path: "apps/docs",
						tasks: {
							items: [{ name: "dev" }, { name: "build" }],
						},
					},
					{
						name: "@stackpanel/ui",
						path: "packages/ui",
						tasks: {
							items: [{ name: "build" }, { name: "lint" }],
						},
					},
					{
						name: "@stackpanel/api",
						path: "packages/api",
						tasks: {
							items: [{ name: "build" }, { name: "check-types" }],
						},
					},
				],
			},
		},
	},
};

export const demoAppVariableLinks = {
	web: {
		dev: {
			DATABASE_URL: "/dev/DATABASE_URL",
			API_BASE_URL: "/var/API_BASE_URL",
		},
	},
	server: {
		dev: {
			DATABASE_URL: "/dev/DATABASE_URL",
			REDIS_URL: "/dev/REDIS_URL",
		},
	},
	docs: {
		dev: {
			API_BASE_URL: "/var/API_BASE_URL",
		},
	},
};

export const demoRecipients = {
	recipients: [
		{
			name: "demo-user",
			publicKey: AGE_DEMO,
			tags: ["dev"],
			source: "users" as const,
			canDelete: false,
		},
		{
			name: "cooper",
			publicKey: AGE_COOPER,
			tags: ["dev", "staging", "prod"],
			source: "users" as const,
			canDelete: false,
		},
	],
};

export const demoSopsAgeKeysStatus = {
	available: true,
	keyCount: 1,
	publicKeys: [AGE_DEMO],
	matchedPublicKeys: [AGE_DEMO],
	recipientMatch: true,
	matchingRecipients: ["demo-user"],
	decryptableGroups: ["dev"],
	keychainService: "stackpanel.sops-age-key",
	userKeyPath: "",
	repoKeyPath: ".stack/keys/local.txt",
	configuredPaths: [".stack/keys/local.txt"],
	configuredOpRefs: [],
	localKeyPath: ".stack/keys/local.txt",
	localKeyExists: true,
	storageTier: "repo",
};

export const demoFiles: Record<string, { exists: boolean; content: string; path: string }> = {
	".stack/gen/codegen/env-warnings.json": {
		path: ".stack/gen/codegen/env-warnings.json",
		exists: true,
		content: JSON.stringify({ schemaVersion: 1, warnings: [] }),
	},
	".stack/secrets/.sops.yaml": {
		path: ".stack/secrets/.sops.yaml",
		exists: true,
		content: [
			"creation_rules:",
			"  - path_regex: \\\\.stack/secrets/vars/dev\\\\.sops\\\\.yaml$",
			"    key_groups:",
			"      - age:",
			"          - " + AGE_DEMO,
			"          - " + AGE_COOPER,
		].join("\n"),
	},
};

export const demoGeneratedFiles = {
	files: [
		{
			path: ".stack/gen/ide/vscode/settings.json",
			enable: true,
			mode: "0644",
			source: "stackpanel.ide.vscode",
			description: "VS Code workspace settings generated by the IDE module",
			existsOnDisk: true,
			isStale: false,
			size: 842,
			contentHash: "demo",
		},
		{
			path: "turbo.json",
			enable: true,
			source: "stackpanel.turbo",
			description: "Turborepo pipeline generated from stackpanel.tasks",
			existsOnDisk: true,
			isStale: false,
			size: 1280,
			contentHash: "demo",
		},
	],
	totalCount: 2,
	staleCount: 0,
	enabledCount: 2,
	lastUpdated: NOW,
};

export const demoNixConfigResponse = {
	configJson: JSON.stringify(demoNixConfig),
	lastUpdated: NOW,
	cached: true,
	source: "demo",
};
