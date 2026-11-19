import type { RegistryModuleVersion } from "@stackpanel/proto/agent/v1/module";
import { Textarea } from "@ui/textarea";

const forge = /^(github|gitlab|sourcehut):([~\w.-]+\/[~\w.-]+)(?:\/(.+))?$/;
const git = /^(?:git\+(?:http|https|file|ssh)|git):/;
const validRef = /^[A-Za-z0-9_][A-Za-z0-9./_+-]*$/;
const revision = /^[a-f\d]{40}$/i;

// Keep non-selector query parameters (notably dir and host) verbatim. On forges
// an immutable rev wins; git URLs can carry both the ref to fetch and its rev.
function inputUrl(raw: string, ref: string, rev: string): string {
  if (!ref && !rev) return raw;
  if (ref && (!validRef.test(ref) || ref.includes("..") || ref.endsWith("/")))
    throw new Error("Invalid Git ref.");
  if (rev && !revision.test(rev)) throw new Error("Invalid Git revision.");
  const split = raw.indexOf("?");
  const base = split < 0 ? raw : raw.slice(0, split);
  const options: string[] = [];
  const hosted = forge.exec(base);
  let originalRef = hosted?.[3] ?? "";
  if (revision.test(originalRef)) originalRef = "";
  if (!hosted && !git.test(base)) throw new Error("A ref override requires a Git source.");
  for (const field of split < 0 ? [] : raw.slice(split + 1).split("&")) {
    if (field.startsWith("ref=")) originalRef = decodeURIComponent(field.slice(4));
    else if (!field.startsWith("rev=")) options.push(field);
  }
  let source = base;
  if (hosted) source = `${hosted[1]}:${hosted[2]}/${rev || ref || originalRef}`;
  else {
    if (ref || originalRef) options.push(`ref=${encodeURIComponent(ref || originalRef)}`);
    if (rev) options.push(`rev=${rev}`);
  }
  return options.length ? `${source}?${options.join("&")}` : source;
}

function nixString(value: string) {
  if (/\p{Cc}/u.test(value)) throw new Error("The input contains invalid characters.");
  return JSON.stringify(value).replaceAll("${", "\\${");
}

function inputLines(name: string, url: string, follows: boolean) {
  const prefix = `inputs.${nixString(name)}`;
  return (
    `${prefix}.url = ${nixString(url)};` +
    (follows ? `\n${prefix}.inputs.nixpkgs.follows = "nixpkgs";` : "")
  );
}

export function ManualFlakeSetup({
  slug,
  release,
  override,
}: {
  slug: string;
  release: RegistryModuleVersion;
  override: string;
}) {
  let snippet: string | undefined;
  let error: string | undefined;
  try {
    const rev = override && override !== release.ref ? "" : release.rev;
    snippet = [
      inputLines(
        slug,
        inputUrl(release.flakeUrl, override || release.ref, rev),
        release.followsNixpkgs,
      ),
      ...release.flakeInputs.map((dep) =>
        inputLines(dep.name, inputUrl(dep.url, dep.ref || "", ""), dep.followsNixpkgs),
      ),
    ].join("\n");
  } catch (cause) {
    error = cause instanceof Error ? cause.message : "Invalid registry input.";
  }
  return (
    <details className="rounded-md border p-3 text-sm">
      <summary>Manual setup · flake.nix</summary>
      <p className="my-2 text-muted-foreground">
        Merge these input declarations into the top-level attribute set of your flake.nix, then lock
        the inputs. Editing this example does not change your project or the Install button.
      </p>
      {snippet ? (
        <Textarea
          key={snippet}
          aria-label="flake.nix input declarations"
          rows={Math.min(12, snippet.split("\n").length + 1)}
          className="font-mono text-xs"
          defaultValue={snippet}
        />
      ) : (
        <p role="alert">Cannot generate this flake snippet: {error}</p>
      )}
      <p className="mt-2 text-muted-foreground">
        Projects without input auto-import need an explicit import of{" "}
        <code>{release.flakePath || "stackpanelModules.default"}</code> from <code>{slug}</code>.
      </p>
    </details>
  );
}
