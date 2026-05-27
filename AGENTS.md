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
