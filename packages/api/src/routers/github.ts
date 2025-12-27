import { TRPCError } from "@trpc/server";
import { z } from "zod/v4";
import { createTRPCRouter, protectedProcedure, publicProcedure } from "../trpc";

// GitHub API types
interface WorkflowRun {
	id: number;
	name: string;
	status: string;
	conclusion: string | null;
	html_url: string;
	created_at: string;
	updated_at: string;
}

interface WorkflowRunsResponse {
	total_count: number;
	workflow_runs: WorkflowRun[];
}

// Snapshot metadata type
interface SnapshotMetadata {
	key: string;
	source_database: string;
	description: string;
	created_at: string;
	created_by: string;
	size: string;
	commit_sha: string;
}

// S3 helper functions
function getS3Config() {
	return {
		endpoint: process.env.S3_ENDPOINT || "",
		bucket: process.env.SEED_SNAPSHOTS_BUCKET || "stackpanel-seeds",
		accessKeyId: process.env.AWS_ACCESS_KEY_ID || "",
		secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || "",
		region: process.env.AWS_REGION || "us-east-1",
	};
}

async function listS3Objects(prefix: string): Promise<string[]> {
	const config = getS3Config();

	// Use AWS SDK if available, otherwise fall back to demo data
	// In production, you would use @aws-sdk/client-s3
	if (!config.accessKeyId) {
		// Return demo data when S3 is not configured
		return [];
	}

	// This is a placeholder - in production use @aws-sdk/client-s3
	// For now, we'll return cached/demo data
	return [];
}

async function getS3Object(key: string): Promise<string | null> {
	const config = getS3Config();

	if (!config.accessKeyId) {
		return null;
	}

	// Placeholder for S3 get operation
	return null;
}

// Get GitHub token from environment
function getGitHubToken(): string {
	const token = process.env.GITHUB_TOKEN;
	if (!token) {
		throw new TRPCError({
			code: "INTERNAL_SERVER_ERROR",
			message: "GitHub token not configured",
		});
	}
	return token;
}

// Get repo info from environment
function getRepoInfo(): { owner: string; repo: string } {
	const owner = process.env.GITHUB_OWNER || "darkmatter";
	const repo = process.env.GITHUB_REPO || "stackpanel";
	return { owner, repo };
}

async function githubFetch<T>(
	endpoint: string,
	options: RequestInit = {},
): Promise<T> {
	const token = getGitHubToken();
	const response = await fetch(`https://api.github.com${endpoint}`, {
		...options,
		headers: {
			Authorization: `Bearer ${token}`,
			Accept: "application/vnd.github+json",
			"X-GitHub-Api-Version": "2022-11-28",
			...options.headers,
		},
	});

	if (!response.ok) {
		const error = await response.text();
		throw new TRPCError({
			code: "INTERNAL_SERVER_ERROR",
			message: `GitHub API error: ${response.status} ${error}`,
		});
	}

	// For 204 No Content responses
	if (response.status === 204) {
		return {} as T;
	}

	return response.json();
}

export const githubRouter = createTRPCRouter({
	/**
	 * Dispatch the provision-db workflow
	 */
	provisionDatabase: protectedProcedure
		.input(
			z.object({
				databaseName: z
					.string()
					.min(1)
					.max(63)
					.regex(/^[a-z][a-z0-9_]*$/, {
						message:
							"Database name must start with a letter and contain only lowercase letters, numbers, and underscores",
					}),
				seedSnapshot: z.string().optional().default(""),
				runMigrations: z.boolean().optional().default(true),
			}),
		)
		.mutation(async ({ input, ctx }) => {
			const { owner, repo } = getRepoInfo();
			const userEmail = ctx.session.user.email;

			if (!userEmail) {
				throw new TRPCError({
					code: "BAD_REQUEST",
					message: "User email is required for database provisioning",
				});
			}

			// Dispatch the workflow
			await githubFetch(
				`/repos/${owner}/${repo}/actions/workflows/provision-db.yml/dispatches`,
				{
					method: "POST",
					body: JSON.stringify({
						ref: "main",
						inputs: {
							database_name: input.databaseName,
							seed_snapshot: input.seedSnapshot,
							run_migrations: String(input.runMigrations),
							requester_email: userEmail,
						},
					}),
				},
			);

			// Wait a moment for the workflow to be created
			await new Promise((resolve) => setTimeout(resolve, 2000));

			// Get the most recent run
			const runs = await githubFetch<WorkflowRunsResponse>(
				`/repos/${owner}/${repo}/actions/workflows/provision-db.yml/runs?per_page=1`,
			);

			const latestRun = runs.workflow_runs[0];

			return {
				success: true,
				message: "Database provisioning started",
				runId: latestRun?.id,
				runUrl: latestRun?.html_url,
			};
		}),

	/**
	 * Get the status of a workflow run
	 */
	getWorkflowRun: protectedProcedure
		.input(z.object({ runId: z.number() }))
		.query(async ({ input }) => {
			const { owner, repo } = getRepoInfo();

			const run = await githubFetch<WorkflowRun>(
				`/repos/${owner}/${repo}/actions/runs/${input.runId}`,
			);

			return {
				id: run.id,
				name: run.name,
				status: run.status,
				conclusion: run.conclusion,
				url: run.html_url,
				createdAt: run.created_at,
				updatedAt: run.updated_at,
			};
		}),

	/**
	 * List recent workflow runs for a specific workflow
	 */
	listWorkflowRuns: protectedProcedure
		.input(
			z.object({
				workflow: z.enum(["provision-db.yml", "publish-snapshot.yml"]),
				limit: z.number().min(1).max(100).optional().default(10),
			}),
		)
		.query(async ({ input }) => {
			const { owner, repo } = getRepoInfo();

			const runs = await githubFetch<WorkflowRunsResponse>(
				`/repos/${owner}/${repo}/actions/workflows/${input.workflow}/runs?per_page=${input.limit}`,
			);

			return {
				total: runs.total_count,
				runs: runs.workflow_runs.map((run) => ({
					id: run.id,
					name: run.name,
					status: run.status,
					conclusion: run.conclusion,
					url: run.html_url,
					createdAt: run.created_at,
					updatedAt: run.updated_at,
				})),
			};
		}),

	/**
	 * Publish a seed snapshot
	 */
	publishSnapshot: protectedProcedure
		.input(
			z.object({
				sourceDatabase: z.string().min(1),
				snapshotName: z
					.string()
					.min(1)
					.max(63)
					.regex(/^[a-z][a-z0-9_-]*$/, {
						message:
							"Snapshot name must start with a letter and contain only lowercase letters, numbers, hyphens, and underscores",
					}),
				description: z.string().optional().default(""),
				makeDefault: z.boolean().optional().default(false),
			}),
		)
		.mutation(async ({ input }) => {
			const { owner, repo } = getRepoInfo();

			// Dispatch the workflow
			await githubFetch(
				`/repos/${owner}/${repo}/actions/workflows/publish-snapshot.yml/dispatches`,
				{
					method: "POST",
					body: JSON.stringify({
						ref: "main",
						inputs: {
							source_database: input.sourceDatabase,
							snapshot_name: input.snapshotName,
							description: input.description,
							make_default: String(input.makeDefault),
						},
					}),
				},
			);

			// Wait a moment for the workflow to be created
			await new Promise((resolve) => setTimeout(resolve, 2000));

			// Get the most recent run
			const runs = await githubFetch<WorkflowRunsResponse>(
				`/repos/${owner}/${repo}/actions/workflows/publish-snapshot.yml/runs?per_page=1`,
			);

			const latestRun = runs.workflow_runs[0];

			return {
				success: true,
				message: "Snapshot publishing started",
				runId: latestRun?.id,
				runUrl: latestRun?.html_url,
			};
		}),

	/**
	 * List available seed snapshots
	 * Returns demo data if S3 is not configured
	 */
	listSnapshots: publicProcedure.query(async () => {
		// Try to list from S3
		const metadataKeys = await listS3Objects("metadata/");

		if (metadataKeys.length === 0) {
			// Return demo snapshots when S3 is not configured
			return {
				snapshots: [
					{
						key: "baseline_20241220_143052",
						sourceDatabase: "seed_master",
						description: "Baseline schema with core tables and indexes",
						createdAt: "2024-12-20T14:30:52Z",
						createdBy: "github-actions[bot]",
						size: "2.4 MB",
						isDefault: true,
					},
					{
						key: "with_sample_data_20241218_091523",
						sourceDatabase: "seed_master",
						description: "Full sample dataset with users, products, and orders",
						createdAt: "2024-12-18T09:15:23Z",
						createdBy: "github-actions[bot]",
						size: "45.2 MB",
						isDefault: false,
					},
					{
						key: "minimal_20241215_162341",
						sourceDatabase: "seed_master",
						description: "Minimal schema only - no seed data",
						createdAt: "2024-12-15T16:23:41Z",
						createdBy: "github-actions[bot]",
						size: "128 KB",
						isDefault: false,
					},
				],
				defaultSnapshot: "baseline_20241220_143052",
			};
		}

		// Parse metadata from S3
		const snapshots = await Promise.all(
			metadataKeys.map(async (key) => {
				const content = await getS3Object(key);
				if (!content) return null;

				try {
					const metadata = JSON.parse(content) as SnapshotMetadata;
					return {
						key: metadata.key,
						sourceDatabase: metadata.source_database,
						description: metadata.description,
						createdAt: metadata.created_at,
						createdBy: metadata.created_by,
						size: metadata.size,
						isDefault: false, // Will be updated below
					};
				} catch {
					return null;
				}
			}),
		);

		// Get default snapshot
		const defaultContent = await getS3Object("default");
		const defaultSnapshot = defaultContent?.trim() || null;

		// Mark default and filter nulls
		const validSnapshots = snapshots
			.filter((s): s is NonNullable<typeof s> => s !== null)
			.map((s) => ({
				...s,
				isDefault: s.key === defaultSnapshot,
			}))
			.sort(
				(a, b) =>
					new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
			);

		return {
			snapshots: validSnapshots,
			defaultSnapshot,
		};
	}),

	/**
	 * Get details for a specific snapshot
	 */
	getSnapshot: publicProcedure
		.input(z.object({ key: z.string() }))
		.query(async ({ input }) => {
			const content = await getS3Object(`metadata/${input.key}.json`);

			if (!content) {
				// Return demo data
				const demoSnapshots: Record<string, SnapshotMetadata> = {
					baseline_20241220_143052: {
						key: "baseline_20241220_143052",
						source_database: "seed_master",
						description: "Baseline schema with core tables and indexes",
						created_at: "2024-12-20T14:30:52Z",
						created_by: "github-actions[bot]",
						size: "2.4 MB",
						commit_sha: "abc123def456",
					},
				};

				const demo = demoSnapshots[input.key];
				if (demo) {
					return {
						key: demo.key,
						sourceDatabase: demo.source_database,
						description: demo.description,
						createdAt: demo.created_at,
						createdBy: demo.created_by,
						size: demo.size,
						commitSha: demo.commit_sha,
					};
				}

				throw new TRPCError({
					code: "NOT_FOUND",
					message: "Snapshot not found",
				});
			}

			const metadata = JSON.parse(content) as SnapshotMetadata;

			return {
				key: metadata.key,
				sourceDatabase: metadata.source_database,
				description: metadata.description,
				createdAt: metadata.created_at,
				createdBy: metadata.created_by,
				size: metadata.size,
				commitSha: metadata.commit_sha,
			};
		}),
});
