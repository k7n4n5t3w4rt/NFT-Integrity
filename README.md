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
| Human-readable CID | `string cidString` — for off-chain display |
| Manifest pointer | `manifestURI` — points to the full JSON manifest (IPFS or otherwise) |
| Authorised derivatives | Mappings with enumeration; only `DERIVATIVE_MANAGER_ROLE` can add/revoke |
| Gateways & mirrors | `RetrievalConfig` struct — updatable by owner without affecting identity |
| Governance | Role-based: `MINTER_ROLE`, `MANIFEST_UPDATER_ROLE`, `DERIVATIVE_MANAGER_ROLE`, owner as `DEFAULT_ADMIN_ROLE` |

### Off-chain (manifest)

The [JSON manifest](schemas/integrity-manifest-v1.schema.json) captures everything that doesn't need on-chain consensus:

- **`canonicalMedia`** — CID, MIME type, and the integrity rule
- **`retrieval`** — preferred and fallback gateways, HTTP mirrors
- **`rights`** — licence CID and summary
- **`governance`** — who can change what, and under what rules
- **`authorisedDerivatives`** — exhibition copies, thumbnails, format conversions

### The `ipfsImport` section — the reproducible recipe

This is the critical section. It records every setting that went into producing the CID from the original bytes. Anyone with an exact copy of the file who imports it with these same settings will get the identical CID. A different setting *anywhere* in this list produces a different CID.

| Setting | Default |
|---|---|
| `implementation` | `kubo` |
| `implementationVersion` | `0.29.0` |
| `cidVersion` | `1` |
| `hashFunction` | `sha2-256` |
| `codec` | `dag-pb` |
| `unixfs` | `true` |
| `rawLeaves` | `true` |
| `chunker` | `size-262144` |
| `pin` | `true` |
| `wrapWithDirectory` | `false` |
| `nocopy` | `false` |
| `inline` | `false` |
| `cidBase` | `base32` |

### What is updatable on-chain

| Thing | Who can change it | Notes |
|---|---|---|
| **`manifestURI`** | `MANIFEST_UPDATER_ROLE` | The manifest lives off-chain. You can move it or re-upload it; only the pointer changes. The CID inside the manifest must still match the canonical CID. |
| **Retrieval config** (gateways, mirrors) | Owner | Gateways come and go. Swapping them out does not touch the artefact's identity — they are just routes. |
| **Authorised derivatives** | `DERIVATIVE_MANAGER_ROLE` | Register an exhibition copy, thumbnail, or format conversion; revoke it if needed. |
| **Roles** | Owner | Who can mint, update manifests, or manage derivatives — all reassignable. |

**What cannot change:** the canonical CID. Once minted, there is no setter, no override, no loophole. That is the point.

## Project structure

```
├── contracts/
│   ├── NFTIntegrity.sol              # Main contract
│   └── interfaces/
│       └── IIntegrityNFT.sol         # Full interface
├── test/
│   └── NFTIntegrity.t.sol           # 29 Foundry tests
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

## Quick start

```bash
# Install dependencies
forge install

# Build
forge build

# Run tests
forge test

# Add your media file to IPFS and get its CID.
# The flags MUST match the ipfsImport settings in the manifest.
# Defaults used by the manifest script:
#   cidVersion=1, hashFunction=sha2-256, codec=dag-pb,
#   chunker=size-262144, rawLeaves=true
ipfs add \
  --cid-version 1 \
  --hash sha2-256 \
  --chunker size-262144 \
  --raw-leaves \
  my-artwork.png
# → added bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi my-artwork.png

# Generate a manifest using the CID you just got.
# The script applies the default ipfsImport settings above; override any
# with dot-path flags, e.g. --ipfsImport.chunker size-1048576
node scripts/create-manifest.js \
  --cid <YOUR-CID> \
  --mime image/png \
  --title "My Work" \
  --artist "Jane Doe" \
  --contract 0x1234567890123456789012345678901234567890 \
  --tokenId 1 \
  --output manifest.json

# Deploy
forge script script/DeployNFTIntegrity.s.sol --broadcast --rpc-url $RPC_URL
```

## What this is not

- It is not a storage layer. It anchors identity on-chain; the manifest and artefact live off-chain (IPFS, archive mirrors).
- It does not enforce the integrity rule mechanically on-chain. It records the CID; verification that a retrieved file matches that CID under the stated import settings is an off-chain operation.
- It does not prescribe a specific gateway or pinning service. The retrieval config is editable so the contract stays useful as infrastructure changes.

## Licence

MIT — see the contract SPDX headers.
