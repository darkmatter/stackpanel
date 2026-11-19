import { toJson, type JsonObject, type JsonValue } from "@bufbuild/protobuf";
import { ValueSchema } from "@bufbuild/protobuf/wkt";
import { ConnectError, type Client } from "@connectrpc/connect";
import type { ModuleService } from "@stackpanel/proto/agent/v1/module";
import { createStore, type StoreApi } from "zustand/vanilla";

export interface ModuleActionRequest {
  moduleId: string;
  actionId: string;
  args: JsonObject;
}

interface Chunk {
  id: number;
  channel: "stdout" | "stderr" | "json";
  text: string;
}

type Status =
  | { kind: "running" }
  | { kind: "exited"; exitCode: number }
  | { kind: "failed"; reason: string };

interface Transcript {
  chunks: Chunk[];
  status: Status;
}

export type ModuleActionOutput = Pick<
  StoreApi<Transcript>,
  "getState" | "getInitialState" | "subscribe"
>;

// Keep a bounded scrollback even if the executable continuously emits output.
const SCROLLBACK_CHUNKS = 1000;

/** Starts exactly one RPC. Observers of `output` may mount, unmount or subscribe late. */
export function startModuleActionStream(
  client: Client<typeof ModuleService> | null,
  request: ModuleActionRequest,
  signal: AbortSignal,
) {
  const output = createStore<Transcript>(() => ({ chunks: [], status: { kind: "running" } }));
  let nextId = 0;
  function append(channel: Chunk["channel"], text: string) {
    const chunks = output.getState().chunks.slice(1 - SCROLLBACK_CHUNKS);
    chunks.push({ id: nextId++, channel, text });
    output.setState({ chunks });
  }

  async function consume() {
    let exitCode: number | undefined;
    let json: JsonValue | undefined;
    try {
      if (!client)
        throw new Error("Module actions are unavailable. Pair an agent and select a project.");
      for await (const { event } of client.runModuleAction(request, { signal })) {
        signal.throwIfAborted();
        if (exitCode !== undefined) throw new Error("Action sent output after its exit code.");
        switch (event.case) {
          case "stdout":
          case "stderr":
            append(event.case, event.value);
            break;
          case "json":
            json = toJson(ValueSchema, event.value);
            append("json", JSON.stringify(json, null, 2));
            break;
          case "exitCode":
            exitCode = event.value;
            break;
          default:
            throw new Error("Unrecognized action stream event.");
        }
      }
      // EOF alone isn't success, nor is an exit code followed by a transport error.
      signal.throwIfAborted();
      if (exitCode === undefined) throw new Error("Action stream ended without an exit code.");
      output.setState({ status: { kind: "exited", exitCode } });
      return { exitCode, json };
    } catch (error) {
      const reason = signal.aborted
        ? "Action stream canceled."
        : ConnectError.from(error).rawMessage;
      output.setState({ status: { kind: "failed", reason } });
      return undefined;
    }
  }

  return { output, finished: consume() };
}
