import { Response } from "@/components/response";

// A Markdown image is a network request even in a closed README disclosure.
// Keep the description, not the src. Links remain explicit navigations.
const elements = [
  "p",
  "a",
  "img",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "ul",
  "ol",
  "li",
  "em",
  "strong",
  "del",
  "blockquote",
  "pre",
  "code",
  "hr",
  "br",
  "table",
  "thead",
  "tbody",
  "tr",
  "th",
  "td",
];
const components = { img: ({ alt }: { alt?: string }) => <span>{alt || "Image omitted"}</span> };

/** Installed and registry documentation share Studio's sanitized Markdown renderer. */
export function ModuleMarkdown({ children }: { children: string }) {
  return (
    <Response
      mode="static"
      skipHtml
      allowedElements={elements}
      components={components}
      className="min-w-0 break-words text-sm"
    >
      {children}
    </Response>
  );
}
