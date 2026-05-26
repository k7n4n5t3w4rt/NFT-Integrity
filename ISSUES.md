# Issues

<!--
  STATUS values: open | in-progress | ready-to-merge | merged
  BRANCH naming: fix/###-short-slug
  Set STATUS to "in-progress", do the work on the listed branch,
  commit, push, then set STATUS to "ready-to-merge" and push again.
-->

---

## Issue 1 — README test count off by one (34 → 35)

- **ID:** 011
- **STATUS:** ready-to-merge
- **BRANCH:** `fix/011-readme-test-count-35`
- **Severity:** Docs
- **File:** `README.md`
- **Problem:** The project structure section says `test/NFTIntegrity.t.sol — 34 Foundry tests`, but the test suite (after the renounceOwnership guard was added for issue 010) now contains 35 tests. `forge test` reports `35 passed; 0 failed`.
- **Fix:** Change "34" to "35" in the README project structure diagram.

---

## Issue 2 — README references deleted remappings.txt

- **ID:** 012
- **STATUS:** ready-to-merge
- **BRANCH:** `fix/012-readme-remove-remappings-txt-ref`
- **Severity:** Docs
- **File:** `README.md`
- **Problem:** `remappings.txt` was deleted in issue 004 to avoid dual sources of truth (remappings live in `foundry.toml`), but the project structure diagram in the README still lists it:
```
└── foundry.toml
```
A user who reads the diagram will look for a file that doesn't exist.
- **Fix:** Remove the `└── remappings.txt` line from the project structure diagram.

---

## Issue 3 — No package.json for Node.js dependency management

- **ID:** 013
- **STATUS:** in-progress
- **BRANCH:** `fix/013-add-package-json`
- **Severity:** DX (Developer Experience)
- **Files:** (new) `package.json`
- **Problem:** README step 7 tells users to `npm install js-sha3` and also references `multiformats/cid` in a code snippet. Without a `package.json`, `npm install` treats the directory as uninitialised — `npm install js-sha3` will either error or pollute the global namespace depending on the user's setup. The `scripts/create-manifest.js` script is self-contained (uses only built-in `fs`/`path`), so it doesn't need npm, but the mint helper snippets scattered through step 7 do.
- **Fix:** Add a minimal `package.json` at the project root that:
  1. Lists `js-sha3` and `multiformats` as devDependencies.
  2. Adds an npm script (`"create-manifest": "node scripts/create-manifest.js"`) so users can run `npm run create-manifest -- --help`.
  3. Adds an npm script to help with the mint encoding (`"cid-to-hex": "node -e \"..."`).
  Update README step 7 to reference `npm run` commands instead of raw snippets.

---

## Issue 4 — Mint helper script missing: Quick Start step 7 is too complex

- **ID:** 014
- **STATUS:** open
- **BRANCH:** `fix/014-add-mint-helper-script`
- **Severity:** Docs / DX
- **Files:** (new) `scripts/mint.js`, `README.md`
- **Problem:** README "Quick Start" step 7 asks a not-very-experienced user to:
  1. Decode a CID string into raw hex bytes using a Node.js snippet that imports `multiformats/cid`.
  2. Compute a `keccak256` manifest content hash using `js-sha3`.
  3. Assemble an 8-argument positional `cast send` call in a specific order: `mint(address,bytes,string,string,string,string,string,bytes32)`.
  Each substep is a friction point where a typo silently produces wrong data. There is no single surface that turns a CID + manifest into a valid mint transaction.
- **Fix:** Add a `scripts/mint.js` helper that:
  1. Reads either a CID string or a manifest file.
  2. Encodes the CID as raw hex (via `multiformats`).
  3. Computes the keccak256 content hash of the manifest (via `js-sha3`).
  4. Prints the complete `cast send` command, or calls `cast send` directly via `child_process.execSync` if `CONTRACT_ADDRESS`, `RPC_URL`, and `PRIVATE_KEY` are set in the environment.
  Update README step 7 to show the simple invocation: `node scripts/mint.js manifest.json --to 0xRecipient --contract $CONTRACT_ADDRESS`.
  The helper script should accept `--dry-run` to print the command without executing it.

---

## Issue 5 — Custom role system silently overwrites existing holders

- **ID:** 015
- **STATUS:** ready-to-merge
- **BRANCH:** `fix/015-document-single-holder-roles`
- **Severity:** Docs
- **File:** `README.md`
- **Problem:** The contract uses a custom `mapping(bytes32 => address)` for roles — each role holds exactly **one** address. `grantRole` silently overwrites the previous holder without a separate revocation step, and there is no way to assign a role to multiple addresses (e.g., no multi-sig or backup minter). The README describes this as "Role-based" using OpenZeppelin-style role constant names (`MINTER_ROLE`, `DEFAULT_ADMIN_ROLE`, etc.), which may lead users to expect OpenZeppelin's `AccessControl` multi-holder semantics.
- **Fix:** Add a note in the README's "On-chain" table (under the Governance row) explicitly stating that roles are **single-address** — each role maps to exactly one account, and granting a role to a new address automatically removes it from the previous holder. This clarifies the design intent without changing the contract.
