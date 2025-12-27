# fumadocs

This is a Next.js application generated with
[Create Fumadocs](https://github.com/fuma-nama/fumadocs).

Run development server:

```bash
bun run dev
```

Open http://localhost:4000 with your browser to see the result.

## Writing Docs

We have an internal documentation generator that automatically generates documenation by one of two methods:

1. **Nix Options Parsing**

We use `nix eval` to generate `nix-options.json` - this is built into nix and gives us the schema of all the options. We then pass this to `stackpanel docgen` which parses this and generates docs using the descriptions for each option. This allows docs and source code to co-exist.

2. **README Parsing**



## Explore

In the project, you can see:

- `lib/source.ts`: Code for content source adapter, [`loader()`](https://fumadocs.dev/docs/headless/source-api) provides the interface to access your content.
- `lib/layout.shared.tsx`: Shared options for layouts, optional but preferred to keep.

| Route | Description |
| ------------------------- | ------------------------------------------------------ |
| `app/(home)` | The route group for your landing page and other pages. |
| `app/docs` | The documentation layout and pages. |
| `app/api/search/route.ts` | The Route Handler for search. |

### Fumadocs MDX

A `source.config.ts` config file has been included, you can customise different options like frontmatter schema.

Read the [Introduction](https://fumadocs.dev/docs/mdx) for further details.

## Learn More

To learn more about Next.js and Fumadocs, take a look at the following
resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js
  features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.
- [Fumadocs](https://fumadocs.dev) - learn about Fumadocs
