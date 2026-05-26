# Issues (ordered by severity)

## 🔴 Critical

1. ~~**`updateManifestURI` enforces an impossible constraint — requires manifest CID to equal media CID**~~ ✅ **DONE (not a bug)**

   `contracts/NFTIntegrity.sol`, `updateManifestURI()`: The function accepts `newManifestCIDString` as a dedicated parameter and validates `newURI == "ipfs://" + newManifestCIDString`. It does **not** compare against the canonical/media CID. The manifest CID is stored on-chain in `TokenIntegrity.manifestCIDString` and updated on each call. The validation is correct — it ensures the manifest URI embeds the manifest's own CID. Both `mint` and `updateManifestURI` follow this pattern. No code change needed.

## 🟡 Medium

2. ~~**MIME type is only off-chain with no on-chain anchor**~~ ✅ **DONE**

   The contract stores `canonicalCID` in `bytes` but never records the MIME type. Any on-chain renderer, marketplace, or verifier has no way to determine whether the canonical CID points to `image/png`, `video/mp4`, `application/pdf`, or something else. This matters for rendering, security, and provenance.

   **Fix:** Add a `mimeType` field to the `TokenIntegrity` struct, set at mint time, or store a content hash of the manifest so the MIME type can be verified against an on-chain anchor.

3. ~~**Rights / licence is only off-chain with no on-chain record**~~ ✅ **DONE**

   The manifest records `rights.licenceCID` and `rights.summary`. The contract stores nothing about the licence. If the manifest URI is updated to a new manifest (once issue #1 is fixed), the licence terms can silently change. There is no on-chain record of what licence was agreed to at mint time.

   **Fix:** Store `licenceCID` on-chain in `TokenIntegrity`, or at minimum record a content hash of the manifest so the licence is cryptographically anchored.

4. ~~**No on-chain commitment to the manifest content hash**~~ ✅ **DONE**

   The contract stores `manifestURI` (a location pointer) but now also stores `manifestContentHash` (a `bytes32` keccak256 hash of the manifest content). This anchors the specific manifest version that was authorised on-chain.

   **Fix applied:** Added `manifestContentHash` (bytes32) field to `TokenIntegrity` struct, `mint()`, `updateManifestURI()`, and both `TokenIntegritySet` / `ManifestURIUpdated` events. The hash is validated as non-zero on mint and update. New tests: `testMintRevertsEmptyManifestContentHash`, `testUpdateManifestURIRevertsEmptyContentHash`.

5. ~~**`authorisedDerivatives` live in two independent places with no sync guarantee**~~ ✅ **DONE**

   The contract has `authoriseDerivative()` / `revokeDerivative()` with on-chain events and enumeration. The manifest also had an `authorisedDerivatives` array. These were independent lists — the manifest was a static snapshot at creation time while the contract is live. They would diverge the moment any derivative was added or revoked.

   **Fix applied:** Removed `authorisedDerivatives` from the manifest (schema, example, and `create-manifest.js`). The on-chain contract is now the single authoritative source for derivative records. Consumers should query `derivativeCount()`, `derivativeAt()`, and `isAuthorisedDerivative()` on-chain. The manifest's `governance.derivativeApprovals` section still documents the governance policy (who approves derivatives), while live state stays on-chain where it belongs.

## 🟠 Architectural

6. ~~**Governance split-brain between manifest and contract**~~ ✅ **DONE**

   **Fix:** Removed `governance` section entirely from the manifest (schema, example, and `create-manifest.js` defaults). The on-chain role system (`DEFAULT_ADMIN_ROLE`, `MANIFEST_UPDATER_ROLE`, `DERIVATIVE_MANAGER_ROLE`) is now the single source of truth for governance. Contract NatSpec updated to reference on-chain governance. README updated with a note explaining that governance is enforced exclusively on-chain.
