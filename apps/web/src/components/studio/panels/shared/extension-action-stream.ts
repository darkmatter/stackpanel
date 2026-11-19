import { toJson } from "@bufbuild/protobuf";
import { ValueSchema } from "@bufbuild/protobuf/wkt";
import type { ActionResult } from "@stackpanel/extension-sdk/protocol";
import type { RunModuleActionResponse } from "@stackpanel/proto/agent/v1/module";

const outputLimit = 1024 * 1024;
const utf8 = new TextEncoder();

/** Abort the actual Connect call before closing its iterator, even on overflow.
 * Dropping an iterator or rejecting the SDK promise alone does not cancel a process. */
export async function collectExtensionAction(
  signal: AbortSignal,
  stream: (signal: AbortSignal) => AsyncIterable<RunModuleActionResponse>,
): Promise<ActionResult> {
  signal.throwIfAborted();
  const controller = new AbortController();
  const abort = () => controller.abort(signal.reason);
  signal.addEventListener("abort", abort, { once: true });
  const result: ActionResult = { stdout: "", stderr: "", exitCode: -1 };
  let remaining = outputLimit;
  let exited = false;
  let events: AsyncIterator<RunModuleActionResponse> | undefined;
  function account(text: string) {
    if (text.length > remaining || (remaining -= utf8.encode(text).byteLength) < 0) {
      throw new Error("Action output exceeds the extension limit");
    }
  }
  try {
    events = stream(controller.signal)[Symbol.asyncIterator]();
    while (true) {
      const chunk = await events.next();
      controller.signal.throwIfAborted();
      if (chunk.done) break;
      if (exited) throw new Error("Action continued after its exit status");
      const { event } = chunk.value;
      switch (event.case) {
        case "stdout":
        case "stderr":
          account(event.value);
          result[event.case] += event.value;
          break;
        case "json": {
          const json = toJson(ValueSchema, event.value);
          account(JSON.stringify(json));
          result.json = json;
          break;
        }
        case "exitCode":
          result.exitCode = event.value;
          exited = true;
          break;
        default:
          throw new Error("Unexpected action stream event");
      }
    }
    if (!exited) throw new Error("Action ended without an exit code");
    return result;
  } finally {
    controller.abort();
    signal.removeEventListener("abort", abort);
    await events?.return?.();
  }
}
