// src/server.ts
import {
  createStartHandler,
  defaultStreamHandler,
  defineHandlerCallback,
} from "@tanstack/react-start/server";
import { createServerEntry } from "@tanstack/react-start/server-entry";

// h3 logs unhandled errors via `console.error(error)`, and Workers Logs only
// keep the JSON-serialized form — HTTPError serializes to
// `{status, unhandled, message}` with no stack and no cause, which makes
// production 500s undebuggable. Expand Error arguments into their stack and
// full cause chain before they reach the console.
const expandError = (value: unknown, depth = 0): string => {
  if (depth > 5) return "[cause chain truncated]";
  if (value instanceof Error) {
    const own = value.stack ?? `${value.name}: ${value.message}`;
    return value.cause === undefined
      ? own
      : `${own}\n[cause] ${expandError(value.cause, depth + 1)}`;
  }
  return typeof value === "string" ? value : JSON.stringify(value);
};
const originalConsoleError = console.error.bind(console);
console.error = (...args: unknown[]) => {
  originalConsoleError(
    ...args.map((a) => (a instanceof Error ? expandError(a) : a)),
  );
};

const customHandler = defineHandlerCallback((ctx) => {
  // add custom logic here
  return defaultStreamHandler(ctx);
});

const fetch = createStartHandler(customHandler);

export default createServerEntry({
  fetch,
});