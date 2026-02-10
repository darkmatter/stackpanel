import { createFromSource } from "fumadocs-core/search/server";
import { source } from "@/lib/source";

// Required for Next.js static export (output: "export")
export const dynamic = "force-static";

// Use staticGET for Next.js static export (output: "export").
// This pre-renders the full Orama search index as a static JSON file
// that the client downloads and searches locally.
const search = createFromSource(source, {
	// https://docs.orama.com/docs/orama-js/supported-languages
	language: "english",
});

export const { staticGET: GET } = search;
