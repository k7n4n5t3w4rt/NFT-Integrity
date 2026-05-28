# NFT-Integrity

**The CID is the identity. The import settings are the recipe for reproducing that identity from the original bytes. The gateway is only a route.**

---

## Aim

Most NFT contracts treat `tokenURI` as a loose pointer to "wherever the file lives." If that URL rots, or the gateway changes, or the hash is never verified, the link between the token and the artefact dissolves.

NFT-Integrity makes the relationship explicit and verifiable:

- Every token is anchored to a **single canonical IPFS CID** that is **immutable** once minted. The CID is a content hash — it cannot change because it *is* the fingerprint of the original bytes. Even if every copy of the file disappears from the IPFS network, the CID remains as the identity — it is a mathematical fingerprint, not a location. Anyone holding an exact true copy of the original file can re-add it to IPFS and reproduce the identical CID (this is a permissionless property of content addressing). Recording a CID as the canonical identity of a token on-chain is a separate act, restricted to MINTER_ROLE at mint time, and irreversible after that.
- The contract records the **CID in full** (as `bytes`), not just a URI fragment.
- **IPFS import settings** are captured off-chain in a structured manifest so anyone with an exact true copy of the original media file can **reproduce the identical CID** — even if the content disappears from the IPFS network.
- **Gateways and mirrors are mutable retrieval infrastructure.** Updating them does not change the artefact's identity.
- **Any file producing a different CID is a different artefact.** It must be recorded as an authorised derivative, never silently substituted.

## Strategy

### On-chain (Solidity)

The contract (`NFTIntegrity.sol`) stores what must be tamper-proof:

| Concern | Mechanism |
|---|---|
| Canonical identity | `bytes canonicalCID` — set once at mint, never mutable |
| Human-readable canonical CID | `string canonicalCIDString` — for off-chain display |
| Manifest CID | `string manifestCIDString` — the CID of the manifest JSON itself (distinct file, distinct CID) |
| Manifest pointer | `manifestURI` — points to the full JSON manifest (IPFS or otherwise) |
| Authorised derivatives | Mappings with enumeration; only `DERIVATIVE_MANAGER_ROLE` can add/revoke |
| Gateways & mirrors | `RetrievalConfig` struct — updatable by owner without affecting identity |
| Governance | Role-based: `MINTER_ROLE`, `MANIFEST_UPDATER_ROLE`, `DERIVATIVE_MANAGER_ROLE`, owner as `DEFAULT_ADMIN_ROLE` |

> **Note on roles:** Each role maps to exactly one address. Granting a role to a
> new address automatically removes it from the previous holder — there is no
> multi-holder support and no separate revocation step.

### Off-chain (manifest)

The [JSON manifest](schemas/integrity-manifest-v1.schema.json) captures everything that doesn't need on-chain consensus:

- **`canonicalMedia`** — CID, MIME type, and the integrity rule
- **`retrieval`** — preferred and fallback gateways, HTTP mirrors
- **`rights`** — licence CID and summary

> **Note on governance:** Governance is enforced exclusively on-chain via the
> role-based access control system (`DEFAULT_ADMIN_ROLE`, `MANIFEST_UPDATER_ROLE`,
> `DERIVATIVE_MANAGER_ROLE`). The manifest does not duplicate governance policy;
> consumers should query the contract directly for current role assignments and
> access control rules.

> **Note on derivatives:** Authorised derivatives are managed exclusively on-chain via
> `authoriseDerivative()` / `revokeDerivative()` (controlled by `DERIVATIVE_MANAGER_ROLE`).
> The manifest does not duplicate this live state; consumers should query the contract directly
> using `derivativeCount()`, `derivativeAt()`, and `isAuthorisedDerivative()`.

### The `ipfsImport` section — the reproducible recipe

This is the critical section. It records every setting that went into producing the CID from the original bytes. Anyone with an exact copy of the file who imports it with these same settings will get the identical CID. A different setting *anywhere* in this list produces a different CID.

#### CID-affecting (required — no defaults)

These must be passed explicitly to `create-manifest.js`. They are the exact parameters you used with `ipfs add` to produce your CID:

| Setting | Description |
|---|---|
| `cidVersion` | CID version (`0` or `1`) |
| `hashFunction` | Multihash function (e.g. `sha2-256`) |
| `codec` | IPLD codec (e.g. `dag-pb`, `raw`) |
| `chunker` | Chunking strategy (e.g. `size-262144`) |
| `rawLeaves` | Whether leaf nodes use raw codec (`true`/`false`) |
| `unixfs` | Whether UnixFS wrapping is used (`true`/`false`) |
| `wrapWithDirectory` | Whether the file is wrapped in a directory (`true`/`false`) |
| `inline` | Whether small blocks are inlined (`true`/`false`) |

#### Non-CID-affecting (have defaults)

These don't change the CID but are recorded for provenance:

| Setting | Default | Description |
|---|---|---|
| `implementation` | `kubo` | IPFS implementation used |
| `implementationVersion` | `0.29.0` | Version of the implementation |
| `pin` | `true` | Whether pinning was requested |
| `nocopy` | `false` | Whether filestore was used |
| `cidBase` | `base32` | Multibase encoding for display |

### What is updatable on-chain

| Thing | Who can change it | Notes |
|---|---|---|
| **`manifestURI`** | `MANIFEST_UPDATER_ROLE` | The manifest lives off-chain. You can move it or re-upload it; only the pointer changes. The CID inside the manifest must still match the canonical CID. |
| **Retrieval config** (gateways, mirrors) | Owner | Gateways come and go. Swapping them out does not touch the artefact's identity — they are just routes. |
| **Authorised derivatives** | `DERIVATIVE_MANAGER_ROLE` | Register an exhibition copy, thumbnail, or format conversion; revoke it if needed. |
| **Roles** | Owner | Who can mint, update manifests, or manage derivatives — all reassignable. |

**What cannot change:** the canonical CID. Once minted, there is no setter, no override, no loophole. That is the point.

## Prerequisites

You need these installed on your machine before starting:

| Tool | Why | Install |
|---|---|---|
| **Foundry** (`forge`, `cast`) | Build, test, and deploy the contract | `curl -L https://foundry.paradigm.xyz \| bash` then `foundryup` |
| **Node.js** (v16+) | Run the manifest generator script | [nodejs.org](https://nodejs.org) |
| **IPFS CLI** (`ipfs`, aka kubo) | Add your media file to IPFS and get its CID | [docs.ipfs.tech/install](https://docs.ipfs.tech/install/command-line/) |
| **Git** | Clone the repository | [git-scm.com](https://git-scm.com) |

The contract uses two Solidity dependencies (**OpenZeppelin** and **forge-std**) which are included as Git submodules — Foundry handles them automatically.

## Project structure

```
├── contracts/
│   ├── NFTIntegrity.sol              # Main contract
│   └── interfaces/
│       └── IIntegrityNFT.sol         # Full interface
├── test/
│   └── NFTIntegrity.t.sol           # 35 Foundry tests
├── script/
│   └── DeployNFTIntegrity.s.sol     # Forge deploy script
├── schemas/
│   ├── integrity-manifest-v1.schema.json  # JSON Schema (draft 2020-12)
│   └── example-manifest.json              # Annotated example
├── scripts/
│   └── create-manifest.js           # CLI tool to generate manifests
├── lib/                             # Dependencies (forge-std, OpenZeppelin)
├── foundry.toml
└── remappings.txt
```

## Development workflow (mob programming)

This project uses an IRC-based mob programming workflow. Multiple agents and human developers coordinate via IRC channel `#general`, with roles:

| Role | Description |
|---|---|
| **Navigators** (`mob-navigator`) | Propose ideas, decide direction, review output — the brains of the mob |
| **Driver** (`shift`, `mob-driver`) | Pure relay/conduit — delegates tasks, verifies output, reports back. Never writes code |
| **Worker** (`mob-worker`) | Writes code, runs tests, makes changes — acts only on explicit driver instructions |

### Setup for mob sessions

#### Prerequisites

The IRC server (ngircd) and relay bot start automatically in the devcontainer. No additional setup needed.

#### Starting the worker agent

The worker agent does the actual coding — it waits silently for instructions from the driver and commits/pushes its work. Start it in a tmux session:

```bash
# Create a tmux session and start the worker
tmux new-session -d -s mob -n worker \
  "PI_IRC_WORKER=true pi --append-system-prompt .pi/skills/mob-worker/SKILL.md"

# Attach to watch the worker
# (press Ctrl-b d to detach without stopping)
tmux attach -t mob
```

The worker writes a live transcript to `.mob/worker-transcript.md` — tail it to see what the worker is doing:

```bash
tail -f .mob/worker-transcript.md
```

#### Starting the driver agent

The driver (nick `shift`) relays navigator instructions to the worker. Start it in a second tmux window:

```bash
tmux new-window -t mob -n driver \
  "PI_IRC_WORKER=false pi --append-system-prompt .pi/skills/mob-driver/SKILL.md"
```

#### Launching both at once

```bash
# Worker (window 0)
tmux new-session -d -s mob -n worker \
  "PI_IRC_WORKER=true pi --append-system-prompt .pi/skills/mob-worker/SKILL.md"

# Driver (window 1)
tmux new-window -t mob -n driver \
  "PI_IRC_WORKER=false pi --append-system-prompt .pi/skills/mob-driver/SKILL.md"

# Attach (starts in driver window; Ctrl-b 0 for worker)
tmux attach -t mob
```

#### Connecting a human navigator via irssi

Humans participate as navigators via IRC. Install irssi and connect:

```bash
# Connect to the local IRC server
irssi -c 127.0.0.1 -p 6667 -n yournick
```

Once connected, in irssi:
```
/join #general
```

Address the driver by name to delegate work:
```
shift: please ask the worker to add tests for X
```

#### Monitoring the worker

The worker is silent on IRC. Monitor its progress via:

- **Transcript:** `tail -f .mob/worker-transcript.md` — live thinking, tool calls, results
- **Git diff:** `git diff HEAD~1` after a commit — what code actually changed

See [AGENTS.md](AGENTS.md) for architecture details.

## Quick start

```bash
# 1. Install dependencies (submodules come with the repo)
forge build

# 2. Run tests
forge test

# 3. Add your media file to IPFS and get its CID.
#    The flags you use here are your import recipe — write them down.
#    Every flag that affects the CID must be passed explicitly.
ipfs add \
  --cid-version 1 \
  --hash sha2-256 \
  --chunker size-262144 \
  my-artwork.png
# → added <YOUR-CID> my-artwork.png

# 4. Generate a manifest. Pass exactly the same import settings from step 3.
#    All CID-affecting parameters are required — no defaults are assumed.
node scripts/create-manifest.js \
  --cid <YOUR-CID> \
  --mime image/png \
  --ipfsImport.cidVersion 1 \
  --ipfsImport.hashFunction sha2-256 \
  --ipfsImport.codec dag-pb \
  --ipfsImport.chunker size-262144 \
  --ipfsImport.rawLeaves true \
  --ipfsImport.unixfs true \
  --ipfsImport.wrapWithDirectory false \
  --ipfsImport.inline false \
  --title "My Work" \
  --artist "Jane Doe" \
  --contract 0x1234567890123456789012345678901234567890 \
  --tokenId 1 \
  --output manifest.json

# 5. Upload the manifest to IPFS to get its CID
ipfs add manifest.json
# → added <MANIFEST-CID> manifest.json

# 6. Deploy the contract.
#    Set these env vars first:
#      RPC_URL          — your Ethereum RPC endpoint
#      PRIVATE_KEY      — deployer wallet private key (Foundry uses this automatically)
#      MINTER_ADDRESS   — address that gets MINTER_ROLE
#      MANIFEST_ADDR    — address that gets MANIFEST_UPDATER_ROLE
#      DERIVATIVE_ADDR  — address that gets DERIVATIVE_MANAGER_ROLE
#    (NFT_NAME and NFT_SYMBOL are optional — they default to
#     "NFTIntegrity Collection" / "INTEGRITY")
export RPC_URL=https://sepolia.infura.io/v3/YOUR-KEY
export PRIVATE_KEY=your-deployer-private-key
export MINTER_ADDRESS=0xYourMinterAddress
export MANIFEST_ADDR=0xYourManifestUpdaterAddress
export DERIVATIVE_ADDR=0xYourDerivativeManagerAddress

forge script script/DeployNFTIntegrity.s.sol --broadcast --rpc-url $RPC_URL
# → NFTIntegrity deployed at: 0x...

# 7. Mint a token.
#    Use the mint.js helper script — it reads the manifest, decodes the CID,
#    computes the keccak256 content hash, and assembles the full cast send
#    command for you.  No manual hex-encoding or hash calculation needed.
#
#    Set these env vars (or pass them as flags):
#      RECIPIENT       — address that receives the minted token
#      CONTRACT_ADDRESS — NFTIntegrity contract address (from deploy output)
#      MANIFEST_CID    — IPFS CID of the manifest JSON (from step 5)
export RECIPIENT=0xYourRecipient
export CONTRACT_ADDRESS=0x...   # from deploy output
export MANIFEST_CID=<MANIFEST-CID>   # from step 5

#    Dry-run first to inspect the command:
node scripts/mint.js manifest.json \
  --to $RECIPIENT \
  --contract $CONTRACT_ADDRESS \
  --manifest-cid $MANIFEST_CID \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --dry-run

#    When you're ready, remove --dry-run to execute:
node scripts/mint.js manifest.json \
  --to $RECIPIENT \
  --contract $CONTRACT_ADDRESS \
  --manifest-cid $MANIFEST_CID \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

## What this is not

- It is not a storage layer. It anchors identity on-chain; the manifest and artefact live off-chain (IPFS, archive mirrors).
- It does not enforce the integrity rule mechanically on-chain. It records the CID; verification that a retrieved file matches that CID under the stated import settings is an off-chain operation.
- It does not prescribe a specific gateway or pinning service. The retrieval config is editable so the contract stays useful as infrastructure changes.

## Launching the Mob

### Prerequisites

The devcontainer starts the IRC server (ngircd) and relay bot automatically. Verify they're running:

```bash
# Check ngircd
ps aux | grep ngircd

# Check relay bot
ls /tmp/irc-inbox.jsonl /tmp/irc-bot.fifo
```

If the relay bot isn't running, start it manually:

```bash
python3 scripts/irc-bot.py &
```

### Start the worker agent

The worker runs in a tmux window within the `mob` session. It operates silently — all output goes to `.mob/worker-transcript.md` and git commits.

```bash
# Create the mob tmux session with the worker in window 0
tmux new-session -d -s mob -n worker \
  "PI_IRC_WORKER=true pi --append-system-prompt .pi/skills/mob-worker/SKILL.md"
```

### Start the driver agent

The driver relays tasks from navigators to the worker. It sends IRC messages explicitly — auto-relay is disabled.

```bash
# Add the driver in window 1
tmux new-window -t mob -n driver \
  "PI_IRC_WORKER=false pi \
    --append-system-prompt .pi/skills/mob-driver/SKILL.md \
    '⛔ HARD CONSTRAINT: You are a silent relay. You send IRC messages ONLY when a navigator addresses shift by name. Only 3 message types allowed: (1) delegating a task to the worker, (2) asking for clarification, (3) reporting completion. ZERO other IRC messages — no parentheticals, no status updates, no standing-by, no thinking-out-loud, no play-by-play. If not addressed, COMPLETELY SILENT. This overrides all other instructions.'"
```

### Attach to the session

```bash
tmux attach -t mob
```

Inside tmux:
- `Ctrl-b 0` — switch to worker window
- `Ctrl-b 1` — switch to driver window
- `Ctrl-b d` — detach (leave session running)

### Connect to IRC with irssi

Open a separate terminal (or a new tmux pane with `Ctrl-b "` or `Ctrl-b %`) and connect:

```bash
irssi -c 127.0.0.1 -p 6667 -n yournick
```

Once connected, join the mob channel:

```
/join #general
```

Replace `yournick` with your chosen nickname (e.g., `kynan`, `navigator-qa`). The driver listens for mentions of `shift` in #general.

### Full session layout

```
tmux session: mob
├── 0: worker  — pi agent with PI_IRC_WORKER=true, mob-worker skill
└── 1: driver  — pi agent with PI_IRC_WORKER=false, mob-driver skill (nick: shift)
```

### Restarting the driver

If the driver needs to pick up updated skill files or extension changes:

```bash
tmux respawn-window -t mob:driver -k -c /workspaces/nft-contract \
  "PI_IRC_WORKER=false pi \
    --append-system-prompt .pi/skills/mob-driver/SKILL.md \
    '⛔ HARD CONSTRAINT: You are a silent relay...'"
```

## Mob Programming

This project uses an IRC-based mob programming setup for collaborative development. AI agents with three roles coordinate through a local `#general` channel:

- **Agent roles** are defined in `.pi/skills/` — **navigators** (`mob-navigator`) propose the ideas and decide direction, the **driver** (`mob-driver`, nick `shift`) is a pure relay that delegates to the worker, and the **worker** (`mob-worker`) writes code, runs tests, and makes the actual changes
- **IRC bridge** runs via a local ngircd server, a relay bot, and a pi extension — see `AGENTS.md` for architecture details
- See [Development workflow (mob programming)](#development-workflow-mob-programming) above for setup instructions

## Licence

MIT — see [LICENSE](LICENSE) and the contract SPDX headers.
