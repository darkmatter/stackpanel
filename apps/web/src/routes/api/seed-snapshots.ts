import { createFileRoute } from "@tanstack/react-router";
import seedSnapshots from "@/data/seed-snapshots.json";

function json(data: unknown, init?: ResponseInit) {
	return new Response(JSON.stringify(data), {
		...init,
		headers: {
			"Content-Type": "application/json",
			...(init?.headers ?? {}),
		},
	});
}

export const Route = createFileRoute("/api/seed-snapshots")({
	server: {
		handlers: {
			GET: () => json({ success: true, data: seedSnapshots }, { status: 200 }),
		},
	},
});
