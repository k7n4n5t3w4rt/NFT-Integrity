# NFT Contract — Agent Context

## IRC Agent Bridge

An IRC-based real-time communication channel is available for agent coordination.

### Architecture

```
irssi ←→ ngircd (127.0.0.1:6667) ←→ irc-bot.py ←→ inbox/FIFO ←→ irc-bridge.ts ←→ pi session
```

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| ngircd server | system (Dockerfile) | IRC server on 127.0.0.1:6667, channel #general |
| irc-bot.py | `./scripts/irc-bot.py` | Relay: IRC ↔ /tmp/irc-inbox.jsonl + /tmp/irc-bot.fifo |
| irc-bridge.ts | `~/.pi/agent/extensions/` | Pi extension: polls inbox, injects into session, relays replies |
| irc-say.sh | `./scripts/irc-say.sh` | Send a message to IRC from the terminal |

### How to use

1. **Connect to IRC**: `irssi -c 127.0.0.1 -p 6667 -n yournick`
2. **Join channel**: `/join #general`
3. **Chat**: Type in irssi — the extension auto-injects messages into this pi session
4. **Manual send**: `./scripts/irc-say.sh "your message"`

### Startup

The devcontainer automatically starts ngircd and the relay bot via `postStartCommand`. The extension loads when pi starts (global discovery from `~/.pi/agent/extensions/`).

### Multi-agent vision

IRC #general is intended as a coordination channel for multi-agent mob programming — different agents with different roles (dev, review, test) all in one channel.

### PI_IRC_WORKER

The IRC bridge extension supports a worker mode (`PI_IRC_WORKER=true`) where it listens to all IRC messages but only acts on instructions from the driver ("shift"). Messages from others are awareness-only context. The worker still relays its responses back to IRC.

## Tmux Session Layout

The mob runs in a tmux session called `mob`:

```
tmux session: mob
├── 0: worker  — pi agent with PI_IRC_WORKER=true, mob-worker skill
└── 1: driver  — pi agent with PI_IRC_WORKER=false, mob-driver skill (nick: shift)
```

### Launching the mob

```bash
# 1. Create the tmux session and launch the worker
tmux new-session -d -s mob -n worker \
  "PI_IRC_WORKER=true pi --append-system-prompt .pi/skills/mob-worker/SKILL.md"

# 2. Launch the driver in a second window
tmux new-window -t mob -n driver \
  "PI_IRC_WORKER=false pi --append-system-prompt .pi/skills/mob-driver/SKILL.md 'You are the mob driver (shift). Set your IRC nick to shift and announce yourself in #general. Then wait for tasks.'"

# 3. Attach
tmux attach -t mob
```

Window naming conventions:
- `worker` — the worker agent (read/write, waits for driver instructions)
- `driver` — the driver agent (shift, only one with authority to delegate)
