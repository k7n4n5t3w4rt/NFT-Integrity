# Issues

<!--
  STATUS values: open | in-progress | ready-to-merge | merged
  BRANCH naming: fix/###-short-slug
  Agents: grep for "STATUS: open" to find the next unclaimed issue.
          Set STATUS to "in-progress", do the work on the listed branch,
          commit, push, then set STATUS to "ready-to-merge" and push again.
-->

---

## Issue 1 — Invalid JSON: trailing comma in schema

- **ID:** 001
- **STATUS:** ready-to-merge
- **BRANCH:** `fix/001-schema-trailing-comma`
- **Severity:** Critical
- **File:** `schemas/integrity-manifest-v1.schema.json`
- **Problem:** Trailing comma after the `rights` property block (line ~223) makes the file invalid JSON. Any JSON parser rejects it.
- **Fix:** Remove the trailing comma after the `rights` closing brace so the top-level object closes cleanly: `}` not `},`.

---

## Issue 2 — Invalid JSON: trailing comma in example manifest

- **ID:** 002
- **STATUS:** open
- **BRANCH:** `fix/002-example-manifest-trailing-comma`
- **Severity:** Critical
- **File:** `schemas/example-manifest.json`
- **Problem:** Trailing comma after the `rights` value (line ~58) makes the file invalid JSON.
- **Fix:** Remove the trailing comma after the `rights` object.

---

## Issue 3 — README: manifestContentHash labels keccak256 but code computes sha256

- **ID:** 003
- **STATUS:** ready-to-merge
- **BRANCH:** `fix/003-readme-hash-docs`
- **Severity:** Bug
- **File:** `README.md`
- **Problem:** The comment in step 7 says "keccak256" but the Node.js snippet uses `crypto.createHash('sha256')`. The contract stores a `bytes32` with no enforced algorithm, so either is valid — but the documentation contradicts itself. Users following the text vs. the code will produce different hashes.
- **Fix:** Pick one algorithm and make the comment match the code. Recommend `keccak256` (Ethereum-native) and update the Node.js snippet to use `keccak256` (requires `js-sha3` or `ethers`).

---

## Issue 4 — Redundant remappings in foundry.toml + remappings.txt

- **ID:** 004
- **STATUS:** open
- **BRANCH:** `fix/004-remove-remappings-txt`
- **Severity:** Config
- **Files:** `foundry.toml`, `remappings.txt`
- **Problem:** Both files define identical remappings. `foundry.toml` already has `remappings = [...]` so `remappings.txt` is redundant. Two sources of truth invite drift.
- **Fix:** Delete `remappings.txt`. Foundry reads `foundry.toml` remappings just fine. Verify `forge build` still passes.

---

## Issue 5 — Dead remapping for @manifoldxyz/libraries-solidity

- **ID:** 005
- **STATUS:** open
- **BRANCH:** `fix/005-remove-manifoldxyz-remapping`
- **Severity:** Config
- **Files:** `foundry.toml`
- **Problem:** No contract imports anything from `@manifoldxyz/libraries-solidity`. The remapping is dead weight and could confuse contributors.
- **Fix:** Remove the `@manifoldxyz/libraries-solidity=` line from `foundry.toml`. Verify `forge build` still passes.

---

## Issue 6 — README: "30 tests" should be "34"

- **ID:** 006
- **STATUS:** open
- **BRANCH:** `fix/006-readme-test-count`
- **Severity:** Docs
- **File:** `README.md`
- **Problem:** The project structure section says `test/NFTIntegrity.t.sol — 30 Foundry tests` but `forge test` reports 34 tests.
- **Fix:** Change "30" to "34" in the README.

---

## Issue 7 — README step 7: mint cast command missing new params

- **ID:** 007
- **STATUS:** open
- **BRANCH:** `fix/007-readme-mint-cast-params`
- **Severity:** Docs
- **File:** `README.md`
- **Problem:** The `cast send` example in the "Quick start" step 7 doesn't include `mimeType`, `licenceCID`, and `manifestContentHash` parameters that the current contract requires. Calling the old signature would revert.
- **Fix:** Update the `cast send` command signature from `"mint(address,bytes,string,string,string)"` to include the three new params, and add the corresponding CLI arguments. (An unstaged diff in the working tree already addresses this — apply and commit it.)

---

## Issue 8 — authorisedDerivatives in manifest defaults but missing from schema

- **ID:** 008
- **STATUS:** open
- **BRANCH:** `fix/008-manifest-authorised-derivatives`
- **Severity:** Inconsistency
- **Files:** `scripts/create-manifest.js`, `schemas/integrity-manifest-v1.schema.json`
- **Problem:** `create-manifest.js` includes `authorisedDerivatives: []` in its DEFAULTS, but the JSON Schema has no `authorisedDerivatives` property. The README states derivatives are managed exclusively on-chain.
- **Fix:** Remove `authorisedDerivatives: []` from `DEFAULTS` in `create-manifest.js` to match both the schema and the stated design intent. Run the script to confirm it still produces valid output.

---

## Issue 9 — fallbackGateways type mismatch: string (Solidity) vs array (schema)

- **ID:** 009
- **STATUS:** open
- **BRANCH:** `fix/009-fallback-gateways-type`
- **Severity:** Inconsistency
- **Files:** `contracts/interfaces/IIntegrityNFT.sol`, `schemas/integrity-manifest-v1.schema.json`, `contracts/NFTIntegrity.sol`
- **Problem:** The Solidity `RetrievalConfig.fallbackGateways` is a `string` (intended for comma-separated or JSON-encoded values), but the JSON Schema defines `fallbackGateways` as `type: "array"` of URI strings. Consumers crossing the on-chain/off-chain boundary must do an implicit conversion with no documented convention.
- **Fix:** Update the Solidity `RetrievalConfig.fallbackGateways` to `string[]` to match the schema. Update `NFTIntegrity.sol` `updateRetrievalConfig` accordingly. Update the tests. Verify `forge build && forge test` pass.

---

## Issue 10 — renounceOwnership not overridden — can brick admin role

- **ID:** 010
- **STATUS:** open
- **BRANCH:** `fix/010-override-renounce-ownership`
- **Severity:** Low
- **File:** `contracts/NFTIntegrity.sol`
- **Problem:** `_transferOwnership` is overridden to keep `_roles[DEFAULT_ADMIN_ROLE]` in sync, and `renounceRole` explicitly prevents renouncing admin. But `renounceOwnership()` (inherited from `Ownable`) is not overridden. Calling it would set `_roles[DEFAULT_ADMIN_ROLE] = address(0)`, permanently bricking role management.
- **Fix:** Override `renounceOwnership()` to revert with a clear message, matching the `renounceRole` guard. Add a test for the revert. Verify `forge build && forge test` pass.

---
