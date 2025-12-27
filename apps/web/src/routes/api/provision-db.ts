import { auth } from "@stackpanel/auth";
import { createFileRoute } from "@tanstack/react-router";

type ProvisionDbRequest = {
	db_name: string;
	snapshot_uri?: string;
	db_user?: string;
	ref?: string;
};

type ProvisionDbResponse = {
	dispatched: boolean;
	workflow: {
		owner: string;
		repo: string;
		workflow: string;
		ref: string;
	};
	run?: {
		id: number;
		status: string;
		conclusion: string | null;
		html_url: string;
	};
};

function json(data: unknown, init?: ResponseInit) {
	return new Response(JSON.stringify(data), {
		...init,
		headers: {
			"Content-Type": "application/json",
			...(init?.headers ?? {}),
		},
	});
}

function getEnv(name: string): string | undefined {
	// Cloudflare Workers (nodejs_compat) provides process.env.
	// Vite may also inline env for server builds; keep it simple.
	// eslint-disable-next-line @typescript-eslint/no-unsafe-member-access
	return (process as any)?.env?.[name] as string | undefined;
}

function requireEnv(name: string): string {
	const v = getEnv(name);
	if (!v) throw new Error(`Missing server env var: ${name}`);
	return v;
}

async function githubFetch(path: string, init: RequestInit) {
	const token =
		getEnv("GITHUB_TOKEN") ??
		getEnv("STACKPANEL_GITHUB_TOKEN") ??
		getEnv("GITHUB_PAT");
	if (!token) throw new Error("Missing GitHub token (set GITHUB_TOKEN)");

	const res = await fetch(`https://api.github.com${path}`, {
		...init,
		headers: {
			Accept: "application/vnd.github+json",
			Authorization: `Bearer ${token}`,
			"X-GitHub-Api-Version": "2022-11-28",
			...(init.headers ?? {}),
		},
	});

	if (!res.ok) {
		const text = await res.text().catch(() => "");
		throw new Error(`GitHub API error ${res.status}: ${text}`);
	}

	return res;
}

async function listRecentRuns(args: {
	owner: string;
	repo: string;
	workflow: string;
	ref: string;
}) {
	const res = await githubFetch(
		`/repos/${args.owner}/${args.repo}/actions/workflows/${encodeURIComponent(
			args.workflow,
		)}/runs?event=workflow_dispatch&branch=${encodeURIComponent(args.ref)}&per_page=5`,
		{ method: "GET" },
	);
	return (await res.json()) as {
		workflow_runs: Array<{
			id: number;
			status: string;
			conclusion: string | null;
			html_url: string;
			created_at: string;
		}>;
	};
}

export const Route = createFileRoute("/api/provision-db")({
	server: {
		handlers: {
			POST: async ({ request }) => {
				const session = await auth.api.getSession({ headers: request.headers });
				if (!session)
					return json(
						{ success: false, error: "unauthorized" },
						{ status: 401 },
					);

				const owner = requireEnv("GITHUB_OWNER");
				const repo = requireEnv("GITHUB_REPO");
				const workflow =
					getEnv("GITHUB_PROVISION_DB_WORKFLOW") ?? "provision-db.yml";
				const defaultRef = getEnv("GITHUB_PROVISION_DB_REF") ?? "main";

				const body = (await request.json()) as ProvisionDbRequest;
				if (!body?.db_name) {
					return json(
						{ success: false, error: "db_name is required" },
						{ status: 400 },
					);
				}

				const ref = body.ref ?? defaultRef;
				const startedAt = Date.now();

				await githubFetch(
					`/repos/${owner}/${repo}/actions/workflows/${encodeURIComponent(
						workflow,
					)}/dispatches`,
					{
						method: "POST",
						headers: { "Content-Type": "application/json" },
						body: JSON.stringify({
							ref,
							inputs: {
								db_name: body.db_name,
								snapshot_uri: body.snapshot_uri ?? "",
								db_user: body.db_user ?? "",
							},
						}),
					},
				);

				// Best-effort: find the created run by polling recent runs after dispatch.
				let run: ProvisionDbResponse["run"] | undefined;
				for (let i = 0; i < 6; i++) {
					const runs = await listRecentRuns({ owner, repo, workflow, ref });
					const candidate = runs.workflow_runs.find((r) => {
						const createdAt = Date.parse(r.created_at);
						return createdAt >= startedAt - 5_000;
					});
					if (candidate) {
						run = {
							id: candidate.id,
							status: candidate.status,
							conclusion: candidate.conclusion,
							html_url: candidate.html_url,
						};
						break;
					}
					await new Promise((r) => setTimeout(r, 1_000));
				}

				const response: ProvisionDbResponse = {
					dispatched: true,
					workflow: { owner, repo, workflow, ref },
					run,
				};
				return json({ success: true, data: response }, { status: 200 });
			},

			GET: async ({ request }) => {
				const session = await auth.api.getSession({ headers: request.headers });
				if (!session)
					return json(
						{ success: false, error: "unauthorized" },
						{ status: 401 },
					);

				const owner = requireEnv("GITHUB_OWNER");
				const repo = requireEnv("GITHUB_REPO");

				const u = new URL(request.url);
				const runId = u.searchParams.get("run_id");
				if (!runId) {
					return json(
						{ success: false, error: "run_id is required" },
						{ status: 400 },
					);
				}

				const res = await githubFetch(
					`/repos/${owner}/${repo}/actions/runs/${encodeURIComponent(runId)}`,
					{ method: "GET" },
				);
				const run = (await res.json()) as {
					id: number;
					status: string;
					conclusion: string | null;
					html_url: string;
				};

				return json(
					{
						success: true,
						data: {
							id: run.id,
							status: run.status,
							conclusion: run.conclusion,
							html_url: run.html_url,
						},
					},
					{ status: 200 },
				);
			},
		},
	},
});
