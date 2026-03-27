export async function runDbProbe() {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    return {
      ok: false as const,
      error: "DATABASE_URL is not configured",
      timestamp: new Date().toISOString(),
    };
  }

  try {
    const url = new URL(databaseUrl);
    const host = url.hostname;
    const user = url.username;
    const password = url.password;
    const database = url.pathname.slice(1);

    const endpoint = `https://${host}/sql`;
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Neon-Connection-String": databaseUrl,
      },
      body: JSON.stringify({
        query: "SELECT NOW() as server_time, current_database() as db_name, version() as pg_version",
        params: [],
      }),
    });

    if (!response.ok) {
      const text = await response.text();
      return {
        ok: false as const,
        error: `DB query failed: ${response.status} ${text}`,
        timestamp: new Date().toISOString(),
      };
    }

    const data = await response.json() as {
      rows: Array<[string, string, string]>;
      fields: Array<{ name: string }>;
    };

    const row = data.rows[0];
    return {
      ok: true as const,
      serverTime: row[0],
      dbName: row[1],
      pgVersion: String(row[2]).split(" ").slice(0, 2).join(" "),
      connectedAs: user,
      database,
      host,
      timestamp: new Date().toISOString(),
    };
  } catch (err: any) {
    return {
      ok: false as const,
      error: err?.message ?? String(err),
      timestamp: new Date().toISOString(),
    };
  }
}
