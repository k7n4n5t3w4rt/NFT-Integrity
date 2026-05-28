import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as fs from "node:fs";

const INBOX = "/tmp/irc-inbox.jsonl";
const FIFO = "/tmp/irc-bot.fifo";
const LAST_SEEN = "/tmp/irc-ext-last-id";

// Worker signal file — the ONLY way a silent worker can talk on IRC.
// Worker writes a one-line message here (e.g., when done with a task).
// The extension picks it up, prefixes it with "WORKER: ", relays to IRC, and deletes it.
// All other worker output (thinking, tool calls, text responses) stays silent.
const WORKER_SIGNAL = "/tmp/worker-irc-signal";

// Worker mode: listen to IRC for driver instructions but NEVER echo responses
// back to IRC. The driver/navigators get info from the transcript log and git diff.
// Set PI_IRC_WORKER=true to enable.
const WORKER_MODE = process.env.PI_IRC_WORKER === "true";

// Observer mode: listen to all IRC messages but only act on messages from
// the driver (shift). Messages from others are awareness-only context.
// Responses are still echoed to IRC (unlike worker mode).
// Set PI_IRC_OBSERVER=true to enable.
const OBSERVER_MODE = process.env.PI_IRC_OBSERVER === "true";

// The driver's IRC nick — only messages from this sender are treated as
// real instructions. Everything else is awareness-only context.
const DRIVER_NICK = "shift";

// Worker and observer use a separate last-seen file to avoid racing with
// the driver. Without this, they read new messages first, update the shared
// counter, and the driver never sees them.
const LAST_SEEN_FILE = (WORKER_MODE || OBSERVER_MODE)
  ? "/tmp/irc-ext-last-id-observer"
  : LAST_SEEN;

export default function (pi: ExtensionAPI) {
  let lastSeenId = 0;
  let ircTurnActive = false;
  let pollTimer: ReturnType<typeof setInterval> | null = null;

  // Restore last seen
  try {
    lastSeenId = parseInt(fs.readFileSync(LAST_SEEN_FILE, "utf-8").trim()) || 0;
  } catch {
    lastSeenId = 0;
  }

  function sendToIrc(text: string) {
    try {
      // IRC doesn't handle embedded newlines — collapse to single line
      // The Python bot handles length-based chunking
      const cleaned = text.trim().replace(/\n+/g, " | ");
      if (cleaned) {
        fs.writeFileSync(FIFO, cleaned);
      }
    } catch {
      // FIFO may not be ready
    }
  }

  // NO auto-relay of assistant responses to IRC.
  // In the mob architecture, agents send IRC messages explicitly via FIFO:
  // - Driver: echo "DRIVER: ..." > /tmp/irc-bot.fifo
  // - Worker: echo "..." > /tmp/worker-irc-signal (gated, only done signal)
  // Auto-relaying assistant text would leak internal monologue to IRC as noise.
  // All IRC output must be intentional and explicit.

  pi.on("agent_end", async () => {
    ircTurnActive = false;
  });

  // Poll IRC inbox and worker signal every 2 seconds
  function checkInbox() {
    // --- Worker signal: gated IRC output channel for silent workers ---
    if (WORKER_MODE) {
      try {
        if (fs.existsSync(WORKER_SIGNAL)) {
          const signal = fs.readFileSync(WORKER_SIGNAL, "utf-8").trim();
          if (signal) {
            sendToIrc(`WORKER: ${signal}`);
          }
          fs.unlinkSync(WORKER_SIGNAL);
        }
      } catch {
        // signal file read error — skip
      }
    }

    // --- IRC inbox ---
    try {
      if (!fs.existsSync(INBOX)) return;
      const data = fs.readFileSync(INBOX, "utf-8").trim();
      if (!data) return;

      const lines = data.split("\n");
      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const entry = JSON.parse(line);
          if (entry.id > lastSeenId) {
            lastSeenId = entry.id;
            fs.writeFileSync(LAST_SEEN_FILE, String(lastSeenId));

            const isDriver = entry.from.toLowerCase() === DRIVER_NICK;

            if (OBSERVER_MODE || WORKER_MODE) {
              if (isDriver) {
                // Driver's messages are real instructions — act on them
                ircTurnActive = true;
                pi.sendUserMessage(`${entry.from} on IRC #general: ${entry.msg}`);
              } else {
                // Everyone else is awareness-only context
                pi.sendUserMessage(`FYI from IRC #general (no action needed — for awareness only): ${entry.from}: ${entry.msg}`);
              }
            } else {
              ircTurnActive = true;
              pi.sendUserMessage(`${entry.from} on IRC #general: ${entry.msg}`);
            }
          }
        } catch {
          // skip malformed lines
        }
      }
    } catch {
      // file read errors
    }
  }

  pollTimer = setInterval(checkInbox, 2000);

  pi.on("session_shutdown", () => {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  });

  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.notify("IRC bridge extension loaded", "info");
  });
}
