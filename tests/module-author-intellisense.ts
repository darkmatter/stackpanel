/// <reference lib="es2024.promise" />
// Run through test-templates.sh against a freshly initialized, locked #module workspace.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import {
  CompletionRequest,
  ConfigurationRequest,
  createProtocolConnection,
  DidChangeTextDocumentNotification,
  DidOpenTextDocumentNotification,
  ExitNotification,
  HoverRequest,
  InitializedNotification,
  InitializeRequest,
  Position,
  PublishDiagnosticsNotification,
  ShutdownRequest,
} from "vscode-languageserver-protocol/node.js";

const workspace = resolve(process.argv[2] ?? ".");
const file = resolve(workspace, "module.nix");
const uri = pathToFileURL(file).href;
const rootUri = pathToFileURL(workspace).href;
const source = await readFile(file, "utf8");
const vs: {
  "nix.enableLanguageServer": boolean;
  "nix.serverPath": string[];
  "nix.serverSettings"?: { nixd?: unknown };
} = JSON.parse(await readFile(resolve(workspace, ".vscode/settings.json"), "utf8"));
const zed: {
  languages: { Nix: { language_servers: string[] } };
  lsp: { nixd: { binary: { path: string; arguments: string[] }; settings?: unknown } };
} = JSON.parse(await readFile(resolve(workspace, ".zed/settings.json"), "utf8"));
assert(vs["nix.enableLanguageServer"] && zed.languages.Nix.language_servers.includes("nixd"));

function cursor(text: string, token: string, typed: string) {
  const index = text.indexOf(token);
  assert(index >= 0, `Missing ${token} in starter module`);
  const prefix = text.slice(0, index + typed.length).split("\n");
  return Position.create(prefix.length - 1, prefix.at(-1)!.length);
}

async function checkEditor(name: string, [command, ...args]: string[], settings: unknown) {
  assert(command, `Missing ${name} Nix server command`);
  const child = spawn(command, args, { cwd: workspace, stdio: ["pipe", "pipe", "inherit"] });
  const lsp = createProtocolConnection(child.stdout, child.stdin);
  const stopped = Promise.withResolvers<never>();
  const deadline = setTimeout(
    () => stopped.reject(new Error(`${name}: timed out waiting for nixd`)),
    60_000,
  );
  child.on("error", stopped.reject);
  child.on("exit", (code) => stopped.reject(new Error(`${name}: nixd exited (${code})`)));
  lsp.onRequest(ConfigurationRequest.type, ({ items }) =>
    items.map(({ section }) => (section === "nixd" ? settings : null)),
  );
  let version = 0;
  let parsed = Promise.withResolvers<void>();
  lsp.onNotification(PublishDiagnosticsNotification.type, (update) => {
    if (update.uri === uri && update.version === version) parsed.resolve();
  });
  // Use unsaved buffers to exercise real partial identifiers rather than asking
  // for symbols already present in the file. Wait for this version's parse.
  async function edit(text: string) {
    parsed = Promise.withResolvers<void>();
    if (++version === 1) {
      await lsp.sendNotification(DidOpenTextDocumentNotification.type, {
        textDocument: { uri, version, languageId: "nix", text },
      });
    } else {
      await lsp.sendNotification(DidChangeTextDocumentNotification.type, {
        textDocument: { uri, version },
        contentChanges: [{ text }],
      });
    }
    await parsed.promise;
  }
  async function expectCompletion(position: Position, expected: string) {
    const response = await lsp.sendRequest(CompletionRequest.type, {
      textDocument: { uri },
      position,
    });
    const items = Array.isArray(response) ? response : response?.items;
    assert(
      items?.some((item) => item.label === expected),
      `${name}: missing completion for ${expected}`,
    );
  }
  async function exercise() {
    lsp.listen();
    await lsp.sendRequest(InitializeRequest.type, {
      processId: process.pid,
      rootUri,
      workspaceFolders: [{ uri: rootUri, name: "example" }],
      capabilities: { workspace: { configuration: true } },
    });
    await lsp.sendNotification(InitializedNotification.type, {});
    for (const [field, prefix] of [
      ["metric", "me"],
      ["label", "la"],
      ["value", "va"],
    ] as const) {
      const text = source.replace(`${field} =`, `${prefix} =`);
      await edit(text);
      await expectCompletion(cursor(source, `${field} =`, prefix), field);
    }
    await edit(source);
    const hover = await lsp.sendRequest(HoverRequest.type, {
      textDocument: { uri },
      position: cursor(source, "label =", "la"),
    });
    const help = JSON.stringify(hover?.contents ?? "");
    assert.match(help, /string/i);
    assert.match(help, /caption/i);
    const helpers = "{ lib, pkgs, ... }: [ lib.stackpanel.ui.met pkgs.hell ]";
    await edit(helpers);
    await expectCompletion(cursor(helpers, "ui.met", "ui.met"), "metric");
    await expectCompletion(cursor(helpers, "pkgs.hell", "pkgs.hell"), "hello");
    await lsp.sendRequest(ShutdownRequest.type);
    await lsp.sendNotification(ExitNotification.type);
    console.log(
      `${name}: completed metric, label and value inside mkModule, SDK helpers and nixpkgs packages; label hover: ${help}`,
    );
  }
  try {
    await Promise.race([exercise(), stopped.promise]);
  } finally {
    clearTimeout(deadline);
    lsp.dispose();
    child.kill();
  }
}

await checkEditor("VS Code", vs["nix.serverPath"], vs["nix.serverSettings"]?.nixd ?? {});
const { binary, settings } = zed.lsp.nixd;
await checkEditor("Zed", [binary.path, ...binary.arguments], settings ?? {});
