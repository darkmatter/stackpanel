const port = Number(process.env.PORT) || 3000;

Bun.serve({
  port,
  async fetch(req) {
    const url = new URL(req.url);
    let path = url.pathname;
    if (path === "/") path = "/index.html";

    const file = Bun.file(`./out${path}`);
    if (await file.exists()) return new Response(file);

    // Try .html extension (Next.js static export convention)
    const html = Bun.file(`./out${path}.html`);
    if (await html.exists()) return new Response(html);

    return new Response(Bun.file("./out/404.html"), { status: 404 });
  },
});

console.log(`Docs server listening on http://localhost:${port}`);
