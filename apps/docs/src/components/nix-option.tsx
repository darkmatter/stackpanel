import { Lock, Package } from "lucide-react";
import { cn } from "@/lib/cn";

interface NixOptionMetaProps {
  /** Nix type string, e.g. "boolean" or "null or string" */
  type: string;
  /**
   * Short (single-line) default value shown as inline code.
   * Multi-line defaults are written as fenced code blocks in the MDX directly.
   */
  defaultValue?: string;
  /** Whether this option is read-only (computed / cannot be set by users). */
  readonly?: boolean;
  /**
   * The module directory name that declared this option, e.g. "deploy",
   * "framework", "bun". Shown as an attribution badge.
   */
  module?: string;
}

/**
 * NixOptionMeta renders an inline metadata row for a single Nix option.
 *
 * It is intentionally NOT a wrapper — it sits below a `## heading` so that
 * Fumadocs can index the heading in the table of contents as normal.
 *
 * Displays: type pill · default value · read-only badge · module badge.
 */
export function NixOptionMeta({
  type,
  defaultValue,
  readonly = false,
  module,
}: NixOptionMetaProps) {
  return (
    <div className="not-prose mb-4 flex flex-wrap items-center gap-2">
      {/* Type */}
      <span className="inline-flex items-center rounded bg-fd-muted px-2 py-0.5 font-mono text-xs text-fd-foreground/80">
        {type}
      </span>

      {/* Default value */}
      {defaultValue !== undefined && (
        <span className="inline-flex items-center gap-1 text-xs text-fd-muted-foreground">
          <span className="opacity-60">default</span>
          <code className="rounded bg-fd-muted px-1.5 py-0.5 font-mono text-xs text-fd-foreground/80">
            {defaultValue}
          </code>
        </span>
      )}

      {/* Read-only badge */}
      {readonly && (
        <span
          className={cn(
            "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-medium",
            "border-amber-300/70 bg-amber-100/80 text-amber-800",
            "dark:border-amber-700/60 dark:bg-amber-900/30 dark:text-amber-300",
          )}
        >
          <Lock className="size-3" aria-hidden />
          read-only
        </span>
      )}

      {/* Module attribution badge */}
      {module && (
        <span
          className={cn(
            "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-medium",
            "border-fd-primary/30 bg-fd-primary/10 text-fd-primary",
          )}
        >
          <Package className="size-3" aria-hidden />
          {module}
        </span>
      )}
    </div>
  );
}
