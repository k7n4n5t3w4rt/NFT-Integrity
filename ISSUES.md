# Issues (ordered by severity)

## 🔴 Medium

1. [x] **`_roles` overwrites silently — no event for displaced holder**  
   `contracts/NFTIntegrity.sol`, `_grantRole()`: When `grantRole()` assigns a role to a new address, the previous holder loses the role without any `RoleRevoked` event.  
   **Fix:** Emit `RoleRevoked` for the previous holder before overwriting.

2. [x] **`Ownable` and `_roles[DEFAULT_ADMIN_ROLE]` can diverge on `transferOwnership`**  
   The contract uses `Ownable` for `onlyOwner` (retrieval config) and `_roles[DEFAULT_ADMIN_ROLE]` for role management. Calling `Ownable.transferOwnership()` changes `_owner` but not `_roles[DEFAULT_ADMIN_ROLE]`, creating two divergent admin states.  
   **Fix:** Override `_transferOwnership` to sync `_roles[DEFAULT_ADMIN_ROLE]`, or remove `Ownable` entirely and use `DEFAULT_ADMIN_ROLE` for all admin checks.

## 🟡 Low

3. [x] **`retrievalConfig` is contract-level, not per-token**  
   All tokens share one gateway configuration. Document this design choice or consider per-token retrieval configs.

4. [x] **`verifyCanonicalCID` uses keccak256-of-CID comparison**  
   Functionally correct but semantically odd (hashing a hash). A direct bytes comparison would work. CIDs are small so gas difference is negligible.

5. [x] **No on-chain enforcement that new manifest CID matches canonical CID**  
   `updateManifestURI` accepts any URI. The README says the manifest CID must match, but this is off-chain trust.  
   **Fix:** Added on-chain enforcement — `newURI` must be exactly `ipfs://` + canonical CID string. Also added `testUpdateManifestURIRevertsCIDMismatch`.

## 🟢 Informational

6. [x] **`create-manifest.js` — dead argument loop**  
   Lines 133-136 iterate over args but the loop body is empty. Remove the dead code.

7. [x] **JSON Schema uses placeholder domain** *(Won't fix)*  
   `$id` is `https://example.org/nft-integrity-manifest/v1`. Use a real domain for production.

8. [x] **`tokenURI` placeholder in `create-manifest.js`**  
   Sets `manifest.token.tokenURI = "ipfs://MANIFEST_CID"` — requires manual replacement after upload.
