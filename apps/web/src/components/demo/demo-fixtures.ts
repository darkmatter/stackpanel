/**
 * Static fixture data powering the /demo Studio.
 *
 * Numbers are deliberately consistent (the Postgres port appears in the
 * apps panel, the variables panel and the dev-shell environment) so the
 * demo feels like a real, coherent project — not a collection of
 * disconnected screenshots.
 */

export const DEMO_PROJECT = {
	name: "acme-platform",
	root: "/Users/sam/code/acme-platform",
	branch: "feat/billing",
	basePort: 6400,
	devshellEntered: true,
	team: [
		{ name: "Sam Carter", email: "sam@acme.dev", role: "owner" },
		{ name: "Priya Anand", email: "priya@acme.dev", role: "admin" },
		{ name: "Jordan Liu", email: "jordan@acme.dev", role: "member" },
		{ name: "Marta Vega", email: "marta@acme.dev", role: "member" },
	],
} as const;

export type DemoApp = {
	id: string;
	name: string;
	stack: string;
	domain: string;
	url: string;
	port: number;
	status: "running" | "stopped" | "building";
	uptime?: string;
	commit: string;
	previewUrl?: string;
	deployTarget?: "Cloudflare Workers" | "Fly.io" | "Hetzner (Colmena)";
};

export const DEMO_APPS: DemoApp[] = [
	{
		id: "web",
		name: "web",
		stack: "TanStack Start · Vite",
		domain: "web.acme.local",
		url: "https://web.acme.local",
		port: 6400,
		status: "running",
		uptime: "2h 14m",
		commit: "f3a4c12",
		previewUrl: "https://feat-billing.web.acme.dev",
		deployTarget: "Cloudflare Workers",
	},
	{
		id: "api",
		name: "api",
		stack: "Hono · Cloudflare Workers",
		domain: "api.acme.local",
		url: "https://api.acme.local",
		port: 6401,
		status: "running",
		uptime: "2h 14m",
		commit: "f3a4c12",
		previewUrl: "https://feat-billing.api.acme.dev",
		deployTarget: "Cloudflare Workers",
	},
	{
		id: "worker",
		name: "worker",
		stack: "Bun + BullMQ",
		domain: "worker.acme.local",
		url: "https://worker.acme.local",
		port: 6402,
		status: "running",
		uptime: "1h 47m",
		commit: "f3a4c12",
		deployTarget: "Fly.io",
	},
	{
		id: "docs",
		name: "docs",
		stack: "Fumadocs · Next.js",
		domain: "docs.acme.local",
		url: "https://docs.acme.local",
		port: 6403,
		status: "building",
		commit: "8b29ee1",
		previewUrl: "https://feat-billing.docs.acme.dev",
		deployTarget: "Cloudflare Workers",
	},
];

export type DemoService = {
	id: string;
	name: string;
	kind: "global" | "network" | "orchestrator";
	status: "running" | "stopped";
	port?: number;
	envVar?: string;
	uptime?: string;
	cpu?: string;
	memory?: string;
	connection?: string;
	notes?: string;
};

export const DEMO_SERVICES: DemoService[] = [
	{
		id: "postgres",
		name: "PostgreSQL 17",
		kind: "global",
		status: "running",
		port: 6410,
		envVar: "STACKPANEL_POSTGRES_PORT",
		uptime: "2h 14m",
		cpu: "0.6%",
		memory: "184 MB",
		connection: "postgresql://acme:****@localhost:6410/acme",
	},
	{
		id: "redis",
		name: "Redis 7",
		kind: "global",
		status: "running",
		port: 6411,
		envVar: "STACKPANEL_REDIS_PORT",
		uptime: "2h 14m",
		cpu: "0.1%",
		memory: "12 MB",
		connection: "redis://localhost:6411/0",
	},
	{
		id: "minio",
		name: "MinIO",
		kind: "global",
		status: "running",
		port: 6412,
		envVar: "STACKPANEL_MINIO_PORT",
		uptime: "2h 14m",
		cpu: "0.4%",
		memory: "92 MB",
		connection: "http://localhost:6412 (console: 6413)",
	},
	{
		id: "caddy",
		name: "Caddy reverse proxy",
		kind: "network",
		status: "running",
		port: 443,
		uptime: "2h 14m",
		cpu: "0.2%",
		memory: "28 MB",
		notes: "Routes *.acme.local → app ports with TLS from Step CA",
	},
	{
		id: "step-ca",
		name: "Step CA",
		kind: "network",
		status: "running",
		port: 9000,
		uptime: "2h 14m",
		cpu: "0.0%",
		memory: "16 MB",
		notes: "Issues per-device certs trusted by your OS root store",
	},
	{
		id: "process-compose",
		name: "process-compose",
		kind: "orchestrator",
		status: "running",
		port: 8080,
		uptime: "2h 14m",
		cpu: "0.1%",
		memory: "22 MB",
		notes: "Supervises all dev processes with health probes",
	},
];

export type DemoVariable = {
	key: string;
	scope: "shared" | "app";
	app?: string;
	dev: string;
	staging: string;
	prod: string;
	encrypted?: boolean;
};

export const DEMO_VARIABLES: DemoVariable[] = [
	{
		key: "DATABASE_URL",
		scope: "shared",
		dev: "postgresql://acme:****@localhost:6410/acme",
		staging: "postgresql://****@neon.tech/acme-staging",
		prod: "postgresql://****@neon.tech/acme-prod",
		encrypted: true,
	},
	{
		key: "REDIS_URL",
		scope: "shared",
		dev: "redis://localhost:6411/0",
		staging: "rediss://****@upstash.io",
		prod: "rediss://****@upstash.io",
		encrypted: true,
	},
	{
		key: "STRIPE_SECRET_KEY",
		scope: "app",
		app: "api",
		dev: "sk_test_****",
		staging: "sk_test_****",
		prod: "sk_live_****",
		encrypted: true,
	},
	{
		key: "RESEND_API_KEY",
		scope: "app",
		app: "api",
		dev: "re_test_****",
		staging: "re_test_****",
		prod: "re_live_****",
		encrypted: true,
	},
	{
		key: "PUBLIC_APP_URL",
		scope: "app",
		app: "web",
		dev: "https://web.acme.local",
		staging: "https://feat-billing.acme.dev",
		prod: "https://app.acme.com",
	},
	{
		key: "FEATURE_BILLING_V2",
		scope: "shared",
		dev: "true",
		staging: "true",
		prod: "false",
	},
];

export type DemoNetworkRoute = {
	host: string;
	target: string;
	tls: boolean;
	app?: string;
	notes?: string;
};

export const DEMO_NETWORK_ROUTES: DemoNetworkRoute[] = [
	{
		host: "web.acme.local",
		target: "http://127.0.0.1:6400",
		tls: true,
		app: "web",
	},
	{
		host: "api.acme.local",
		target: "http://127.0.0.1:6401",
		tls: true,
		app: "api",
	},
	{
		host: "worker.acme.local",
		target: "http://127.0.0.1:6402",
		tls: true,
		app: "worker",
	},
	{
		host: "docs.acme.local",
		target: "http://127.0.0.1:6403",
		tls: true,
		app: "docs",
	},
	{
		host: "minio.acme.local",
		target: "http://127.0.0.1:6412",
		tls: true,
		notes: "Object storage console + S3 API",
	},
];

export type DemoGenerated = {
	path: string;
	tool: string;
	bytes: number;
	updated: string;
};

export const DEMO_GENERATED_FILES: DemoGenerated[] = [
	{
		path: ".vscode/settings.json",
		tool: "stackpanel.ide",
		bytes: 4_822,
		updated: "2 minutes ago",
	},
	{
		path: ".vscode/extensions.json",
		tool: "stackpanel.ide",
		bytes: 1_204,
		updated: "2 minutes ago",
	},
	{
		path: ".zed/settings.json",
		tool: "stackpanel.ide",
		bytes: 2_109,
		updated: "2 minutes ago",
	},
	{
		path: "process-compose.yaml",
		tool: "stackpanel.process-compose",
		bytes: 7_680,
		updated: "2 minutes ago",
	},
	{
		path: "Caddyfile",
		tool: "stackpanel.network.caddy",
		bytes: 3_412,
		updated: "2 minutes ago",
	},
	{
		path: "packages/gen/env/src/web.ts",
		tool: "stackpanel.secrets",
		bytes: 5_604,
		updated: "8 minutes ago",
	},
	{
		path: "packages/gen/env/src/api.ts",
		tool: "stackpanel.secrets",
		bytes: 6_241,
		updated: "8 minutes ago",
	},
	{
		path: "apps/web/wrangler.jsonc",
		tool: "stackpanel.deploy.alchemy",
		bytes: 2_905,
		updated: "1 hour ago",
	},
];

export type DemoActivity = {
	at: string;
	actor: string;
	icon:
		| "deploy"
		| "secret"
		| "shell"
		| "code"
		| "warn"
		| "user";
	title: string;
	detail?: string;
};

export const DEMO_ACTIVITY: DemoActivity[] = [
	{
		at: "2 min ago",
		actor: "sam@acme.dev",
		icon: "shell",
		title: "Entered devshell",
		detail: "13 services healthy · 0 warnings",
	},
	{
		at: "8 min ago",
		actor: "sam@acme.dev",
		icon: "code",
		title: "Edited .stack/config.nix",
		detail: "Added api.app.cron.enable = true",
	},
	{
		at: "12 min ago",
		actor: "priya@acme.dev",
		icon: "secret",
		title: "Rotated STRIPE_SECRET_KEY (prod)",
		detail: "Re-keyed for 4 recipients",
	},
	{
		at: "47 min ago",
		actor: "ci",
		icon: "deploy",
		title: "Deployed feat-billing → preview",
		detail: "alchemy · web, api, docs · 28s",
	},
	{
		at: "1 hour ago",
		actor: "jordan@acme.dev",
		icon: "user",
		title: "Joined the team",
		detail: "Added AGE recipient and re-keyed dev secrets",
	},
	{
		at: "3 hours ago",
		actor: "ci",
		icon: "warn",
		title: "Flake check warning",
		detail: "Unused module argument `lib` in apps/worker",
	},
];

export const DEMO_HEALTH = {
	devshellHash: "sha256-9f1c…74ab",
	flakeCheck: "passing" as const,
	openPorts: 13,
	teamRecipients: 4,
	encryptedFiles: 6,
	disk: "12.4 GB available",
	processesUp: 13,
	processesTotal: 13,
};
