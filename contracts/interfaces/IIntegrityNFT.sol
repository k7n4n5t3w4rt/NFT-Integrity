// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title IIntegrityNFT
/// @notice Interface for CID-centric NFT with artefact integrity guarantees.
///
/// The central rule: the CID is the identity. Import settings are the recipe
/// for reproducing that identity from the original bytes. Gateways are only routes.
interface IIntegrityNFT is IERC721 {

    // ─── Roles ───────────────────────────────────────────────────────────

    /// @notice Role holding DEFAULT_ADMIN_ROLE (owner). Can grant/revoke all other roles.
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    /// @notice Role allowed to mint tokens and set canonical CIDs.
    function MINTER_ROLE() external view returns (bytes32);

    /// @notice Role allowed to update the manifest URI for a token.
    function MANIFEST_UPDATER_ROLE() external view returns (bytes32);

    /// @notice Role allowed to authorise or revoke derivative CIDs.
    function DERIVATIVE_MANAGER_ROLE() external view returns (bytes32);

    // ─── Structs ─────────────────────────────────────────────────────────

    /// @param canonicalCID          Full IPFS CID bytes of the canonical artefact (multibase-prefixed).
    /// @param canonicalCIDString    Readable CID string of the canonical artefact (e.g. "bafybei...").
    /// @param manifestCIDString     CID of the integrity manifest JSON (separate file, distinct CID).
    /// @param manifestURI           URI pointing to the integrity manifest (e.g. "ipfs://<manifestCID>").
    /// @param mimeType              MIME type of the canonical artefact (e.g. "image/png", "video/mp4").
    /// @param licenceCID            CID of the licence document (e.g. "bafy..."). Anchors rights on-chain.
    /// @param manifestContentHash   keccak256 hash of the manifest content. Anchors the
    ///                              specific manifest version on-chain so consumers can detect
    ///                              if the manifest at the URI has been swapped.
    /// @param ipfsImportKey         Reference to the IPFS import settings used (manifest key).
    struct TokenIntegrity {
        bytes   canonicalCID;
        string  canonicalCIDString;
        string  manifestCIDString;
        string  manifestURI;
        string  mimeType;
        string  licenceCID;
        bytes32 manifestContentHash;
        string  ipfsImportKey;
    }

    /// @param derivativeCID    CID of the authorised derivative.
    /// @param derivedFromCID   The canonical CID this derives from.
    /// @param role             Purpose of the derivative (e.g. "exhibition-copy").
    /// @param authorisedBy     Address that authorised this derivative.
    /// @param authorisedAt     Block timestamp of authorisation.
    /// @param active           Whether this derivative is currently authorised.
    struct Derivative {
        bytes   derivativeCID;
        bytes   derivedFromCID;
        string  role;
        address authorisedBy;
        uint256 authorisedAt;
        bool    active;
    }

    /// @param preferredGateway Primary IPFS gateway for retrieval.
    /// @param fallbackGateways Fallback gateways (comma-separated or JSON array).
    /// @param mirrors          Array of HTTP mirror URIs.
    ///
    /// @dev RetrievalConfig is intentionally contract-level, not per-token.
    /// Gateways represent retrieval infrastructure ("how to reach IPFS"),
    /// which is a collection-wide concern. The CID in TokenIntegrity already
    /// provides content addressing independent of any specific gateway.
    struct RetrievalConfig {
        string   preferredGateway;
        string   fallbackGateways;
        string[] mirrors;
    }

    // ─── Events ──────────────────────────────────────────────────────────

    event TokenIntegritySet(
        uint256 indexed tokenId,
        bytes   canonicalCID,
        string  canonicalCIDString,
        string  manifestCIDString,
        string  manifestURI,
        string  mimeType,
        string  licenceCID,
        bytes32 manifestContentHash
    );

    event ManifestURIUpdated(
        uint256 indexed tokenId,
        string  oldURI,
        string  newURI,
        string  newManifestCIDString,
        bytes32 newManifestContentHash
    );

    event DerivativeAuthorised(
        uint256 indexed tokenId,
        bytes   derivativeCID,
        string  role,
        address authorisedBy
    );

    event DerivativeRevoked(
        uint256 indexed tokenId,
        bytes   derivativeCID
    );

    event RetrievalConfigUpdated(
        string  preferredGateway,
        uint256 fallbackCount,
        uint256 mirrorCount
    );

    event RoleGranted(bytes32 indexed role, address indexed account);
    event RoleRevoked(bytes32 indexed role, address indexed account);

    // ─── Role Management ─────────────────────────────────────────────────

    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantRole(bytes32 roleId, address account) external;
    function revokeRole(bytes32 roleId) external;
    function renounceRole(bytes32 roleId) external;

    // ─── Token Integrity ─────────────────────────────────────────────────

    /// @notice Mint a new token with its canonical CID, manifest CID, manifest URI, and MIME type.
    /// @dev Canonical CID is immutable once set. Only MINTER_ROLE.
    /// @param manifestCIDString  The CID of the manifest file itself (distinct from canonicalCID).
    /// @param manifestURI        Full URI pointing to the manifest (e.g. "ipfs://<manifestCID>").
    /// @param mimeType              MIME type of the canonical artefact (e.g. "image/png", "video/mp4").
    /// @param licenceCID            CID of the licence document. Anchors rights on-chain.
    /// @param manifestContentHash   keccak256 hash of the manifest content. Anchors the
    ///                              specific manifest version on-chain.
    function mint(
        address to,
        bytes   calldata canonicalCID,
        string  calldata canonicalCIDString,
        string  calldata manifestCIDString,
        string  calldata manifestURI,
        string  calldata mimeType,
        string  calldata licenceCID,
        bytes32 manifestContentHash
    ) external returns (uint256 tokenId);

    /// @notice Get the integrity record for a token.
    function tokenIntegrity(uint256 tokenId)
        external
        view
        returns (TokenIntegrity memory);

    /// @notice Verify that a given CID matches the canonical CID for a token.
    function verifyCanonicalCID(uint256 tokenId, bytes calldata cid)
        external
        view
        returns (bool);

    // ─── Manifest Management ─────────────────────────────────────────────

    /// @notice Update the manifest URI and manifest CID for a token.
    /// @param newManifestCIDString  The CID of the manifest file itself (distinct from canonicalCID).
    /// @param newURI                Full URI pointing to the manifest (e.g. "ipfs://<manifestCID>").
    /// @param newManifestContentHash keccak256 hash of the new manifest content. Anchors the
    ///                               specific manifest version on-chain.
    /// @dev Only MANIFEST_UPDATER_ROLE. The canonical CID does NOT change.
    /// The CID embedded in `newURI` (everything after `ipfs://`) must match
    /// `newManifestCIDString` — this is enforced on-chain.
    function updateManifestURI(
        uint256 tokenId,
        string  calldata newManifestCIDString,
        string  calldata newURI,
        bytes32 newManifestContentHash
    ) external;

    // ─── Derivatives ─────────────────────────────────────────────────────

    /// @notice Authorise a derivative CID for a token.
    /// @dev Only DERIVATIVE_MANAGER_ROLE.
    function authoriseDerivative(
        uint256 tokenId,
        bytes   calldata derivativeCID,
        string  calldata role
    ) external;

    /// @notice Revoke a previously authorised derivative.
    function revokeDerivative(uint256 tokenId, bytes calldata derivativeCID)
        external;

    /// @notice Check if a CID is an authorised derivative of a token.
    function isAuthorisedDerivative(uint256 tokenId, bytes calldata cid)
        external
        view
        returns (bool);

    /// @notice Get derivative info.
    function getDerivative(uint256 tokenId, bytes calldata derivativeCID)
        external
        view
        returns (Derivative memory);

    /// @notice Get count of authorised derivatives for a token.
    function derivativeCount(uint256 tokenId)
        external
        view
        returns (uint256);

    /// @notice Get an authorised derivative by index.
    function derivativeAt(uint256 tokenId, uint256 index)
        external
        view
        returns (Derivative memory);

    // ─── Retrieval Configuration ─────────────────────────────────────────

    /// @notice Get the retrieval configuration (gateways and mirrors).
    function retrievalConfig()
        external
        view
        returns (RetrievalConfig memory);

    /// @notice Update retrieval gateways. Only owner (DEFAULT_ADMIN_ROLE).
    function updateRetrievalConfig(
        string calldata preferredGateway,
        string calldata fallbackGateways,
        string[] calldata mirrors
    ) external;
}
