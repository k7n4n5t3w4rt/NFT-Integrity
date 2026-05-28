/**
 * Worker Transcript Logger
 *
 * Writes a human-readable markdown transcript of the worker's session to
 * .mob/worker-transcript.md. The driver and navigators can tail this file
 * to stay current with what the worker is doing — thinking, tool calls,
 * results, and final responses.
 *
 * Only active when PI_IRC_WORKER=true (worker mode).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as fs from "node:fs";
import * as path from "node:path";

const TRANSCRIPT_PATH = ".mob/worker-transcript.md";

function formatTimestamp(): string {
  return new Date().toISOString().replace("T", " ").replace(/\..+/, "");
}

function appendToTranscript(text: string) {
  try {
    fs.appendFileSync(TRANSCRIPT_PATH, text);
  } catch {
    // silently skip if file not writable
  }
}

export default function (pi: ExtensionAPI) {
  // Only log in worker mode
  if (process.env.PI_IRC_WORKER !== "true") return;

  let turnIndex = 0;

  // Initialize transcript on session start
  pi.on("session_start", async (_event, ctx) => {
    const cwd = ctx.cwd;
    const sessionFile = ctx.sessionManager.getSessionFile() ?? "ephemeral";
    const dir = path.dirname(TRANSCRIPT_PATH);
    try {
      fs.mkdirSync(path.resolve(cwd, dir), { recursive: true });
    } catch { /* ok */ }

    const header = [
      `# Worker Transcript`,
      ``,
      `- **Session:** \`${sessionFile}\``,
      `- **CWD:** \`${cwd}\``,
      `- **Started:** ${formatTimestamp()}`,
      ``,
      `---`,
      ``,
    ].join("\n") + "\n";

    fs.writeFileSync(path.resolve(cwd, TRANSCRIPT_PATH), header);
  });

  // Track turns
  pi.on("turn_start", async () => {
    turnIndex++;
  });

  // Capture all messages as they finalize
  pi.on("message_end", async (event) => {
    const msg = event.message;
    const ts = formatTimestamp();

    if (msg.role === "user") {
      const text = Array.isArray(msg.content)
        ? msg.content.filter((b: any) => b.type === "text").map((b: any) => b.text).join("\n")
        : String(msg.content ?? "");

      if (!text.trim()) return;

      appendToTranscript([
        `### 🧭 Instruction / Context (turn ${turnIndex}) — ${ts}`,
        ``,
        text,
        ``,
        `---`,
        ``,
      ].join("\n") + "\n");
    }

    if (msg.role === "assistant") {
      const blocks = Array.isArray(msg.content) ? msg.content : [];

      const thinking = blocks
        .filter((b: any) => b.type === "thinking")
        .map((b: any) => b.thinking)
        .join("\n");

      const text = blocks
        .filter((b: any) => b.type === "text")
        .map((b: any) => b.text)
        .join("\n");

      const toolCalls = blocks
        .filter((b: any) => b.type === "toolCall")
        .map((b: any) =>
          `Tool call \`${b.name}\` (\`${b.id}\`):\n\n\`\`\`json\n${JSON.stringify(b.arguments, null, 2)}\n\`\`\``
        )
        .join("\n\n");

      const parts: string[] = [];
      parts.push(`### 🤖 Assistant (turn ${turnIndex}) — ${ts}`);

      if (thinking) {
        parts.push(``);
        parts.push(`<details><summary>💭 Thinking...</summary>`);
        parts.push(``);
        parts.push(thinking);
        parts.push(``);
        parts.push(`</details>`);
      }

      if (text) {
        parts.push(``);
        parts.push(text);
      }

      if (toolCalls) {
        parts.push(``);
        parts.push(`**Tool calls:**`);
        parts.push(``);
        parts.push(toolCalls);
      }

      parts.push(``);
      parts.push(`---`);
      parts.push(``);

      appendToTranscript(parts.join("\n") + "\n");
    }

    if (msg.role === "toolResult") {
      const toolMsg = msg as any;
      const text = Array.isArray(toolMsg.content)
        ? toolMsg.content.filter((b: any) => b.type === "text").map((b: any) => b.text).join("\n")
        : String(toolMsg.content ?? "");

      const status = toolMsg.isError ? "❌" : "✅";
      const maxLen = 2000;
      const displayText = text.length > maxLen
        ? text.slice(0, maxLen) + `\n\n> _(truncated, ${text.length - maxLen} more chars)_`
        : text;

      appendToTranscript([
        `#### ${status} Tool result: \`${toolMsg.toolName}\` (call \`${toolMsg.toolCallId}\`) — ${ts}`,
        ``,
        "```",
        displayText,
        "```",
        ``,
      ].join("\n") + "\n");
    }
  });
}
