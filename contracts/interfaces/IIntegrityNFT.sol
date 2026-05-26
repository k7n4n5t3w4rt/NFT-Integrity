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

    /// @param cid              Full IPFS CID bytes (multibase-prefixed).
    /// @param cidString        Readable CID string (e.g. "bafybei...").
    /// @param manifestURI      URI pointing to the integrity manifest JSON.
    /// @param ipfsImportKey    Reference to the IPFS import settings used (manifest key).
    struct TokenIntegrity {
        bytes   cid;
        string  cidString;
        string  manifestURI;
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
    struct RetrievalConfig {
        string   preferredGateway;
        string   fallbackGateways;
        string[] mirrors;
    }

    // ─── Events ──────────────────────────────────────────────────────────

    event TokenIntegritySet(
        uint256 indexed tokenId,
        bytes   cid,
        string  cidString,
        string  manifestURI
    );

    event ManifestURIUpdated(
        uint256 indexed tokenId,
        string  oldURI,
        string  newURI
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

    /// @notice Mint a new token with its canonical CID and manifest URI.
    /// @dev Canonical CID is immutable once set. Only MINTER_ROLE.
    function mint(
        address to,
        bytes   calldata canonicalCID,
        string  calldata cidString,
        string  calldata manifestURI
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

    /// @notice Update the manifest URI for a token.
    /// @dev Only MANIFEST_UPDATER_ROLE. The canonical CID does NOT change.
    function updateManifestURI(uint256 tokenId, string calldata newURI)
        external;

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
