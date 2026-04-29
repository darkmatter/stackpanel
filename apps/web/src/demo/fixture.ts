/**
 * Frozen fixture data for the demo agent.
 *
 * Mirrors the shape of `.stack/state/stack.json` plus the entity tables the
 * studio reads through the agent's REST surface. Treat it as immutable from
 * the handler side; if a handler simulates a write, mutate a shallow clone.
 */

export const DEMO_HOST = "demo-agent.stackpanel.local";
export const DEMO_PORT = 9876;
export const DEMO_BASE_URL = `http://${DEMO_HOST}:${DEMO_PORT}`;

export const demoStateJson = {
	version: 1,
	projectName: "stackpanel-demo",
	basePort: 6400,
	paths: {
		state: ".stack/state",
		gen: ".stack/gen",
		data: ".stack",
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
			port: 6410,
			envVar: "STACKPANEL_POSTGRES_PORT",
		},
		redis: {
			key: "REDIS",
			name: "Redis",
			port: 6411,
			envVar: "STACKPANEL_REDIS_PORT",
		},
		minio: {
			key: "MINIO",
			name: "MinIO",
			port: 6412,
			envVar: "STACKPANEL_MINIO_PORT",
		},
	},
	network: {
		step: { enable: false, caUrl: null },
	},
} as const;

export const demoNixConfig = {
	stack: {
		enable: true,
		name: "stackpanel-demo",
		root: "/home/demo/stackpanel-demo",
		apps: demoStateJson.apps,
		services: demoStateJson.services,
		ports: { basePort: demoStateJson.basePort, modulus: 100 },
		users: {
			"demo-user": {
				name: "Demo User",
				email: "demo@stackpanel.com",
				github: "stackpanel-demo",
			},
		},
		theme: { palette: "tokyo-night" },
	},
} as const;

export const demoEntities: Record<string, Record<string, unknown>> = {
	apps: {
		web: { name: "web", port: 6402, domain: "stackpanel-demo.localhost" },
		server: { name: "server", port: 6401 },
		docs: { name: "docs", port: 6400, domain: "docs.stackpanel-demo.localhost" },
	},
	services: demoStateJson.services as Record<string, unknown>,
	users: {
		"demo-user": {
			name: "Demo User",
			email: "demo@stackpanel.com",
			github: "stackpanel-demo",
		},
	},
	variables: {
		NODE_ENV: { value: "development", scope: "all" },
		LOG_LEVEL: { value: "info", scope: "all" },
	},
	tasks: {
		dev: { command: "bun run dev", description: "Start dev servers" },
		build: { command: "bun run build", description: "Build all apps" },
	},
	"generated-files": {},
};

export const demoHealth = {
	status: "ok",
	projectRoot: "/home/demo/stackpanel-demo",
	hasProject: true,
	agentId: "demo-agent",
	version: "demo",
};

/**
 * Synthetic "project" entries returned for `/api/project/list` and
 * `/api/project/current` in demo mode. Shape mirrors the agent's actual
 * response so `ProjectProvider` and `ProjectSelector` work unchanged.
 */
export const demoProject = {
	id: "demo",
	name: "stackpanel-demo",
	path: "/home/demo/stackpanel-demo",
	active: true,
	is_default: true,
	last_opened: new Date().toISOString(),
} as const;

/** Process-compose snapshot for the overview panel's ProcessStateCard */
export const demoProcessComposeProcesses = {
	processes: [
		{
			name: "web",
			namespace: "default",
			status: "Running",
			is_running: true,
			restarts: 0,
			pid: 12_345,
			age_ms: 1_800_000,
		},
		{
			name: "server",
			namespace: "default",
			status: "Running",
			is_running: true,
			restarts: 0,
			pid: 12_346,
			age_ms: 1_800_000,
		},
		{
			name: "postgres",
			namespace: "services",
			status: "Running",
			is_running: true,
			restarts: 0,
			pid: 12_347,
			age_ms: 3_600_000,
		},
		{
			name: "redis",
			namespace: "services",
			status: "Running",
			is_running: true,
			restarts: 0,
			pid: 12_348,
			age_ms: 3_600_000,
		},
	],
} as const;
