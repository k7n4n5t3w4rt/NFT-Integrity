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
- **`ipfsImport`** — implementation (`kubo`), CID version, hash function, codec, chunker settings — the reproducible recipe
- **`retrieval`** — preferred and fallback gateways, HTTP mirrors
- **`rights`** — licence CID and summary
- **`governance`** — who can change what, and under what rules
- **`authorisedDerivatives`** — exhibition copies, thumbnails, format conversions

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

# Generate a manifest
node scripts/create-manifest.js \
  --cid bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi \
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
