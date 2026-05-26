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
└── foundry.toml
```

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
#    The contract's mint() takes the raw binary CID as bytes — you need to
#    decode the CID string to hex first. One way: use Node.js:
#      node -e "const {CID} = require('multiformats/cid');
#               CID.parse('<YOUR-CID>').bytes.then(b =>
#                 console.log('0x' + Buffer.from(b).toString('hex')))"
#
#    Or encode it with the @ipld/dag-pb tooling. Alternatively, call mint()
#    through Etherscan's UI or a script that handles the CID encoding.
#
#    You also need the manifestContentHash — the keccak256 hash of the
#    manifest JSON content. Compute it with js-sha3:
#      npm install js-sha3
#      node -e "const keccak256 = require('js-sha3').keccak256;
#               const fs = require('fs');
#               const buf = fs.readFileSync('manifest.json');
#               console.log('0x' + keccak256(buf))"
#
#    The canonicalCIDString, manifestCIDString, manifestURI, mimeType,
#    licenceCID, and manifestContentHash fill out the remaining parameters:
export CONTRACT_ADDRESS=0x...   # from deploy output
cast send $CONTRACT_ADDRESS \
  "mint(address,bytes,string,string,string,string,string,bytes32)" \
  0xYourRecipientAddress \
  0x<RAW-CID-HEX> \
  "<YOUR-CID>" \
  "<MANIFEST-CID>" \
  "ipfs://<MANIFEST-CID>" \
  "image/png" \
  "<LICENCE-CID>" \
  0x<MANIFEST-CONTENT-HASH> \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL
```

## What this is not

- It is not a storage layer. It anchors identity on-chain; the manifest and artefact live off-chain (IPFS, archive mirrors).
- It does not enforce the integrity rule mechanically on-chain. It records the CID; verification that a retrieved file matches that CID under the stated import settings is an off-chain operation.
- It does not prescribe a specific gateway or pinning service. The retrieval config is editable so the contract stays useful as infrastructure changes.

## Licence

MIT — see [LICENSE](LICENSE) and the contract SPDX headers.
