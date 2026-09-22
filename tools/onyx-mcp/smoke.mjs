#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// The smallest thing that fails if the server is broken.
//
// Spawns `server.mjs` over stdio exactly as Claude Desktop does, completes the
// handshake, lists the tools and calls one. It needs NO Supabase credentials:
// with none set, every tool answers "Not configured: …", which is itself the
// assertion — a tool that can report its own missing configuration is a tool
// that registered, took its arguments and ran its handler.
//
//     npm --prefix tools/onyx-mcp install
//     npm --prefix tools/onyx-mcp run smoke
//
// With `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` and `ONYX_USER_ID` in the
// environment it goes further and lists the real exports.
// ─────────────────────────────────────────────────────────────────────────────

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const configured = Boolean(
  process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY && process.env.ONYX_USER_ID
);

const transport = new StdioClientTransport({
  command: process.execPath,
  args: [join(here, "server.mjs")],
  env: process.env,
});

const client = new Client({ name: "onyx-mcp-smoke", version: "1.0.0" });
await client.connect(transport);

const { tools } = await client.listTools();
console.log(`onyx-mcp — ${tools.length} tools\n`);
for (const tool of tools) {
  const args = Object.keys(tool.inputSchema?.properties ?? {});
  console.log(`  ${tool.name}(${args.join(", ")})`);
  console.log(`      ${tool.description.split(". ")[0]}.`);
}

const expected = ["list_exports", "get_export", "get_latest_markdown", "query_sets", "get_daily_scores"];
const missing = expected.filter((name) => !tools.some((tool) => tool.name === name));
if (missing.length) {
  console.error(`\nFAIL — missing tools: ${missing.join(", ")}`);
  process.exit(1);
}

console.log(`\nCalling list_exports…`);
const result = await client.callTool({ name: "list_exports", arguments: { limit: 3 } });
const text = result.content.map((part) => part.text).join("\n");
console.log(text.slice(0, 600));

if (!configured) {
  // Unconfigured is the expected shape here, and it has to be an ERROR result:
  // a handler that swallowed a missing key and returned `[]` would look
  // identical to an athlete who has never exported.
  if (!result.isError || !text.startsWith("Not configured")) {
    console.error("\nFAIL — expected a 'Not configured' tool error with no credentials set.");
    process.exit(1);
  }
  console.log("\nOK — 5 tools, handshake clean, unconfigured call reports itself.");
  console.log("     Set SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY and ONYX_USER_ID to go further.");
} else {
  if (result.isError) {
    console.error(`\nFAIL — list_exports errored: ${text}`);
    process.exit(1);
  }
  console.log("\nOK — 5 tools, handshake clean, list_exports answered from the live database.");
}

await client.close();
