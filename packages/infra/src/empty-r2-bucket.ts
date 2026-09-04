import { loaders } from "@gen/env";

/**
 * Empty an R2 bucket via the Cloudflare management API so Alchemy can delete
 * it. Alchemy's R2 provider refuses to wipe objects unless `forceDestroy` was
 * set on the resource; the leftover OpenNext incremental-cache bucket was
 * created without that flag.
 *
 * Missing buckets are a no-op (already gone).
 *
 * Usage: bun packages/infra/src/empty-r2-bucket.ts <bucket-name>
 */
const bucket = process.argv[2];
if (!bucket) {
  console.error("usage: bun packages/infra/src/empty-r2-bucket.ts <bucket-name>");
  process.exit(1);
}

await loaders.deploy({ inject: true, validate: true });

const accountId = process.env.CLOUDFLARE_ACCOUNT_ID;
const token = process.env.CLOUDFLARE_API_TOKEN;
if (!accountId || !token) {
  throw new Error("CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN are required");
}

const base = `https://api.cloudflare.com/client/v4/accounts/${accountId}/r2/buckets/${bucket}/objects`;
const headers = { Authorization: `Bearer ${token}` };

let deleted = 0;
for (;;) {
  const page = await listPage();
  if (page === "missing") {
    if (deleted === 0) {
      console.log(`[empty-r2] ${bucket} does not exist; nothing to empty`);
    } else {
      console.log(`[empty-r2] ${bucket} disappeared after deleting ${deleted} objects`);
    }
    process.exit(0);
  }
  if (page.keys.length === 0) break;
  await deleteKeys(page.keys);
  deleted += page.keys.length;
  console.log(`[empty-r2] deleted ${deleted} objects from ${bucket}`);
}

console.log(`[empty-r2] ${bucket} is empty (${deleted} objects removed)`);

type ListPage = "missing" | { keys: string[] };

async function listPage(): Promise<ListPage> {
  const url = new URL(base);
  url.searchParams.set("per_page", "1000");
  const res = await fetch(url, { headers });
  if (res.status === 404) return "missing";
  const body = (await res.json()) as {
    success?: boolean;
    errors?: { message?: string; code?: number }[];
    result?: { key?: string }[];
  };
  if (res.status === 404 || isMissingBucket(res.status, body.errors)) {
    return "missing";
  }
  if (!res.ok || body.success === false) {
    throw new Error(
      `list ${bucket} failed: ${res.status} ${JSON.stringify(body.errors ?? body)}`,
    );
  }
  return {
    keys: (body.result ?? []).flatMap((obj) => (obj.key ? [obj.key] : [])),
  };
}

async function deleteKeys(keys: string[]): Promise<void> {
  const batchSize = 20;
  for (let i = 0; i < keys.length; i += batchSize) {
    const batch = keys.slice(i, i + batchSize);
    await Promise.all(
      batch.map(async (key) => {
        const encoded = key.split("/").map(encodeURIComponent).join("/");
        const res = await fetch(`${base}/${encoded}`, {
          method: "DELETE",
          headers,
        });
        if (res.status === 404) return;
        if (!res.ok) {
          const text = await res.text();
          throw new Error(`delete ${key} failed: ${res.status} ${text}`);
        }
      }),
    );
  }
}

function isMissingBucket(
  status: number,
  errors: { message?: string; code?: number }[] | undefined,
): boolean {
  if (status === 404) return true;
  const message = (errors ?? []).map((e) => e.message ?? "").join(" ");
  return /not found|does not exist|NoSuchBucket/i.test(message);
}
