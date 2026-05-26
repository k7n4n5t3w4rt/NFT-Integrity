// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IIntegrityNFT.sol";

/// @title NFTIntegrity
/// @notice CID-centric ERC-721 contract where the IPFS CID is the canonical
///         artefact identity. Import settings are stored off-chain in the
///         manifest; gateways are treated as mutable retrieval infrastructure.
///
/// Central rule:
///   The CID is the identity. The import settings are the recipe for
///   reproducing that identity from the original bytes. The gateway is
///   only a route.
///
/// Governance model (on-chain, single source of truth):
///   • Canonical CID:  immutable once minted
///   • Manifest URI:   updatable by MANIFEST_UPDATER_ROLE
///   • Derivatives:    authorised/revoked by DERIVATIVE_MANAGER_ROLE
///   • Gateways:       updatable by owner (DEFAULT_ADMIN_ROLE)
///   • Roles:          grant/revoke by DEFAULT_ADMIN_ROLE
contract NFTIntegrity is ERC721URIStorage, Ownable, IIntegrityNFT {

    // ─── Role definitions (as bytes32 constants for interface compliance) ─

    bytes32 public constant MINTER_ROLE             = keccak256("MINTER_ROLE");
    bytes32 public constant MANIFEST_UPDATER_ROLE   = keccak256("MANIFEST_UPDATER_ROLE");
    bytes32 public constant DERIVATIVE_MANAGER_ROLE = keccak256("DERIVATIVE_MANAGER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE      = keccak256("DEFAULT_ADMIN_ROLE");

    // ─── Role → address mappings ─────────────────────────────────────────

    mapping(bytes32 => address) private _roles;

    // ─── Token counter ───────────────────────────────────────────────────

    uint256 private _nextTokenId;

    // ─── Token integrity storage ─────────────────────────────────────────

    // Struct field cid renamed to canonicalCID for clarity:
    // it is the canonical artefact CID, not any CID.
    mapping(uint256 => TokenIntegrity) private _tokenIntegrity;

    // ─── Derivatives storage ─────────────────────────────────────────────
    // tokenId => derivativeCID hash => Derivative
    mapping(uint256 => mapping(bytes32 => Derivative)) private _derivatives;
    // tokenId => array of derivative CID hashes (for enumeration)
    mapping(uint256 => bytes32[]) private _derivativeKeys;
    // tokenId => derivativeCID hash => index in array (for O(1) removal)
    mapping(uint256 => mapping(bytes32 => uint256)) private _derivativeIndex;

    // ─── Retrieval configuration ─────────────────────────────────────────
    //
    // Design note: RetrievalConfig is contract-level (shared by all tokens),
    // not per-token. Gateways describe *how* to retrieve content from IPFS —
    // they are collection-wide infrastructure, not per-artefact metadata.
    // Every token records its own canonical CID (content address), so the
    // same gateway config suffices regardless of which token's content is
    // being fetched. If per-token gateways are needed, that should be
    // modelled in the off-chain manifest instead.

    RetrievalConfig private _retrievalConfig;

    // ─── Constructor ─────────────────────────────────────────────────────

    /// @param name            ERC-721 token name.
    /// @param symbol          ERC-721 token symbol.
    /// @param minter          Address granted MINTER_ROLE.
    /// @param manifestUpdater Address granted MANIFEST_UPDATER_ROLE.
    /// @param derivativeMgr   Address granted DERIVATIVE_MANAGER_ROLE.
    constructor(
        string memory name,
        string memory symbol,
        address minter,
        address manifestUpdater,
        address derivativeMgr
    )
        ERC721(name, symbol)
    {
        _nextTokenId = 1;

        // Owner is implicitly DEFAULT_ADMIN_ROLE
        _roles[DEFAULT_ADMIN_ROLE] = msg.sender;

        _grantRole(MINTER_ROLE,             minter);
        _grantRole(MANIFEST_UPDATER_ROLE,   manifestUpdater);
        _grantRole(DERIVATIVE_MANAGER_ROLE, derivativeMgr);
    }

    // ─── Role Management ─────────────────────────────────────────────────

    /// @notice Check if an account holds a role.
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role] == account;
    }

    /// @notice Grant a role to an account. Only DEFAULT_ADMIN_ROLE.
    function grantRole(bytes32 roleId, address account) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        _grantRole(roleId, account);
    }

    /// @notice Revoke a role from an account. Only DEFAULT_ADMIN_ROLE.
    function revokeRole(bytes32 roleId) external {
        _checkRole(DEFAULT_ADMIN_ROLE);
        require(roleId != DEFAULT_ADMIN_ROLE, "NFTIntegrity: cannot revoke admin");
        address previous = _roles[roleId];
        _roles[roleId] = address(0);
        emit RoleRevoked(roleId, previous);
    }

    /// @notice Renounce a role held by the caller.
    function renounceRole(bytes32 roleId) external {
        require(hasRole(roleId, msg.sender), "NFTIntegrity: not role holder");
        require(roleId != DEFAULT_ADMIN_ROLE, "NFTIntegrity: cannot renounce admin");
        _roles[roleId] = address(0);
        emit RoleRevoked(roleId, msg.sender);
    }

    /// @notice Override Ownable._transferOwnership to keep _roles[DEFAULT_ADMIN_ROLE]
    ///         in sync with the Ownable owner. Without this, transferOwnership()
    ///         would change _owner but not the role mapping, creating two
    ///         divergent admin states.
    function _transferOwnership(address newOwner) internal virtual override {
        super._transferOwnership(newOwner);

        address previousAdmin = _roles[DEFAULT_ADMIN_ROLE];
        if (previousAdmin != address(0)) {
            emit RoleRevoked(DEFAULT_ADMIN_ROLE, previousAdmin);
        }

        _roles[DEFAULT_ADMIN_ROLE] = newOwner;

        if (newOwner != address(0)) {
            emit RoleGranted(DEFAULT_ADMIN_ROLE, newOwner);
        }
    }

    // ─── Minting ─────────────────────────────────────────────────────────

    /// @inheritdoc IIntegrityNFT
    function mint(
        address to,
        bytes   calldata canonicalCID,
        string  calldata canonicalCIDString,
        string  calldata manifestCIDString,
        string  calldata manifestURI,
        string  calldata mimeType,
        string  calldata licenceCID,
        bytes32 manifestContentHash
    )
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 tokenId)
    {
        require(canonicalCID.length > 0, "NFTIntegrity: empty CID");
        require(bytes(canonicalCIDString).length > 0, "NFTIntegrity: empty CID string");
        require(bytes(manifestCIDString).length > 0, "NFTIntegrity: empty manifest CID string");
        require(bytes(mimeType).length > 0, "NFTIntegrity: empty mime type");
        require(bytes(licenceCID).length > 0, "NFTIntegrity: empty licence CID");
        require(manifestContentHash != bytes32(0), "NFTIntegrity: empty manifest content hash");

        // Validate that manifestURI matches the manifest CID.
        bytes memory uriBytes    = bytes(manifestURI);
        bytes memory mcidBytes   = bytes(manifestCIDString);
        bytes memory prefix      = bytes("ipfs://");
        require(
            uriBytes.length == prefix.length + mcidBytes.length,
            "NFTIntegrity: manifest URI length mismatch"
        );
        for (uint i = 0; i < prefix.length; i++) {
            require(uriBytes[i] == prefix[i], "NFTIntegrity: URI must start with ipfs://");
        }
        for (uint i = 0; i < mcidBytes.length; i++) {
            require(uriBytes[i + prefix.length] == mcidBytes[i], "NFTIntegrity: manifest URI must match manifest CID");
        }

        tokenId = _nextTokenId++;

        _tokenIntegrity[tokenId] = TokenIntegrity({
            canonicalCID:       canonicalCID,
            canonicalCIDString: canonicalCIDString,
            manifestCIDString:  manifestCIDString,
            manifestURI:        manifestURI,
            mimeType:           mimeType,
            licenceCID:         licenceCID,
            manifestContentHash: manifestContentHash,
            ipfsImportKey:      "ipfsImport"
        });

        _safeMint(to, tokenId);

        // Use the manifest URI as the ERC-721 tokenURI for metadata.
        if (bytes(manifestURI).length > 0) {
            _setTokenURI(tokenId, manifestURI);
        }

        emit TokenIntegritySet(tokenId, canonicalCID, canonicalCIDString, manifestCIDString, manifestURI, mimeType, licenceCID, manifestContentHash);
    }

    // ─── Token Integrity ─────────────────────────────────────────────────

    /// @inheritdoc IIntegrityNFT
    function tokenIntegrity(uint256 tokenId)
        external
        view
        returns (TokenIntegrity memory)
    {
        _requireMinted(tokenId);
        return _tokenIntegrity[tokenId];
    }

    /// @inheritdoc IIntegrityNFT
    function verifyCanonicalCID(uint256 tokenId, bytes calldata cid)
        external
        view
        returns (bool)
    {
        _requireMinted(tokenId);
        // Compare via hash — Solidity does not support == across bytes storage
        // and bytes calldata. CIDs are small, so gas difference is negligible.
        return keccak256(abi.encodePacked(_tokenIntegrity[tokenId].canonicalCID))
            == keccak256(abi.encodePacked(cid));
    }

    // ─── Manifest Management ─────────────────────────────────────────────

    /// @inheritdoc IIntegrityNFT
    function updateManifestURI(
        uint256 tokenId,
        string  calldata newManifestCIDString,
        string  calldata newURI,
        bytes32 newManifestContentHash
    )
        external
        onlyRole(MANIFEST_UPDATER_ROLE)
    {
        _requireMinted(tokenId);

        require(newManifestContentHash != bytes32(0), "NFTIntegrity: empty manifest content hash");

        // Enforce that the CID embedded in newURI (the part after "ipfs://")
        // matches the supplied manifest CID string.
        bytes memory newURIBytes = bytes(newURI);
        bytes memory newMancid   = bytes(newManifestCIDString);
        bytes memory prefix      = bytes("ipfs://");

        require(
            newURIBytes.length == prefix.length + newMancid.length,
            "NFTIntegrity: manifest URI length mismatch"
        );
        for (uint i = 0; i < prefix.length; i++) {
            require(
                newURIBytes[i] == prefix[i],
                "NFTIntegrity: URI must start with ipfs://"
            );
        }
        for (uint i = 0; i < newMancid.length; i++) {
            require(
                newURIBytes[i + prefix.length] == newMancid[i],
                "NFTIntegrity: manifest CID must match supplied manifest CID"
            );
        }

        string memory oldURI = _tokenIntegrity[tokenId].manifestURI;
        _tokenIntegrity[tokenId].manifestCIDString = newManifestCIDString;
        _tokenIntegrity[tokenId].manifestURI = newURI;
        _tokenIntegrity[tokenId].manifestContentHash = newManifestContentHash;

        // Keep ERC-721 tokenURI in sync.
        _setTokenURI(tokenId, newURI);

        emit ManifestURIUpdated(tokenId, oldURI, newURI, newManifestCIDString, newManifestContentHash);
    }

    // ─── Derivatives ─────────────────────────────────────────────────────

    /// @inheritdoc IIntegrityNFT
    function authoriseDerivative(
        uint256 tokenId,
        bytes   calldata derivativeCID,
        string  calldata role
    )
        external
        onlyRole(DERIVATIVE_MANAGER_ROLE)
    {
        _requireMinted(tokenId);

        bytes32 key = keccak256(derivativeCID);
        require(!_derivatives[tokenId][key].active, "NFTIntegrity: already authorised");

        _derivatives[tokenId][key] = Derivative({
            derivativeCID:  derivativeCID,
            derivedFromCID: _tokenIntegrity[tokenId].canonicalCID,
            role:           role,
            authorisedBy:   msg.sender,
            authorisedAt:   block.timestamp,
            active:         true
        });

        _derivativeIndex[tokenId][key] = _derivativeKeys[tokenId].length;
        _derivativeKeys[tokenId].push(key);

        emit DerivativeAuthorised(tokenId, derivativeCID, role, msg.sender);
    }

    /// @inheritdoc IIntegrityNFT
    function revokeDerivative(uint256 tokenId, bytes calldata derivativeCID)
        external
        onlyRole(DERIVATIVE_MANAGER_ROLE)
    {
        _requireMinted(tokenId);

        bytes32 key = keccak256(derivativeCID);
        require(_derivatives[tokenId][key].active, "NFTIntegrity: not authorised");

        _derivatives[tokenId][key].active = false;

        // Remove from enumeration array (swap-and-pop).
        uint256 index = _derivativeIndex[tokenId][key];
        uint256 lastIndex = _derivativeKeys[tokenId].length - 1;

        if (index != lastIndex) {
            bytes32 lastKey = _derivativeKeys[tokenId][lastIndex];
            _derivativeKeys[tokenId][index] = lastKey;
            _derivativeIndex[tokenId][lastKey] = index;
        }
        _derivativeKeys[tokenId].pop();
        delete _derivativeIndex[tokenId][key];

        emit DerivativeRevoked(tokenId, derivativeCID);
    }

    /// @inheritdoc IIntegrityNFT
    function isAuthorisedDerivative(uint256 tokenId, bytes calldata cid)
        external
        view
        returns (bool)
    {
        _requireMinted(tokenId);
        return _derivatives[tokenId][keccak256(cid)].active;
    }

    /// @inheritdoc IIntegrityNFT
    function getDerivative(uint256 tokenId, bytes calldata derivativeCID)
        external
        view
        returns (Derivative memory)
    {
        _requireMinted(tokenId);
        Derivative memory d = _derivatives[tokenId][keccak256(derivativeCID)];
        require(d.active, "NFTIntegrity: not an active derivative");
        return d;
    }

    /// @inheritdoc IIntegrityNFT
    function derivativeCount(uint256 tokenId)
        external
        view
        returns (uint256)
    {
        _requireMinted(tokenId);
        return _derivativeKeys[tokenId].length;
    }

    /// @inheritdoc IIntegrityNFT
    function derivativeAt(uint256 tokenId, uint256 index)
        external
        view
        returns (Derivative memory)
    {
        _requireMinted(tokenId);
        require(index < _derivativeKeys[tokenId].length, "NFTIntegrity: index out of bounds");
        return _derivatives[tokenId][_derivativeKeys[tokenId][index]];
    }

    // ─── Retrieval Configuration ─────────────────────────────────────────

    /// @inheritdoc IIntegrityNFT
    function retrievalConfig()
        external
        view
        returns (RetrievalConfig memory)
    {
        return _retrievalConfig;
    }

    /// @inheritdoc IIntegrityNFT
    function updateRetrievalConfig(
        string calldata preferredGateway,
        string calldata fallbackGateways,
        string[] calldata mirrors
    )
        external
        onlyOwner
    {
        _retrievalConfig.preferredGateway = preferredGateway;
        _retrievalConfig.fallbackGateways = fallbackGateways;

        // Replace mirrors array.
        delete _retrievalConfig.mirrors;
        for (uint256 i = 0; i < mirrors.length; i++) {
            _retrievalConfig.mirrors.push(mirrors[i]);
        }

        emit RetrievalConfigUpdated(
            preferredGateway,
            bytes(fallbackGateways).length > 0 ? 1 : 0,
            mirrors.length
        );
    }

    // ─── ERC-165 ─────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IIntegrityNFT).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // ─── Internal helpers ────────────────────────────────────────────────

    function _requireMinted(uint256 tokenId) internal view override {
        require(_exists(tokenId), "NFTIntegrity: token does not exist");
    }

    function _grantRole(bytes32 role, address account) internal {
        require(account != address(0), "NFTIntegrity: zero address");
        address previous = _roles[role];
        if (previous != address(0)) {
            emit RoleRevoked(role, previous);
        }
        _roles[role] = account;
        emit RoleGranted(role, account);
    }

    modifier onlyRole(bytes32 requiredRole) {
        _checkRole(requiredRole);
        _;
    }

    function _checkRole(bytes32 roleId) internal view {
        require(hasRole(roleId, msg.sender), "NFTIntegrity: not authorised for this role");
    }
}
