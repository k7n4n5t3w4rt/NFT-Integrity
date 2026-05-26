// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../contracts/NFTIntegrity.sol";
import "forge-std/Test.sol";

/// @title NFTIntegrityTest
/// @notice Tests for the CID-centric NFTIntegrity contract.
contract NFTIntegrityTest is Test {

    NFTIntegrity public nft;

    // Test accounts
    address public admin        = address(0xA);
    address public minter       = address(0xB);
    address public manifestUpd  = address(0xC);
    address public derivativeMgr = address(0xD);
    address public user         = address(0xE);

    // Sample CID (real CIDv1 in base32 with dag-pb, sha2-256 — "hello world")
    bytes  public constant SAMPLE_CID_BYTES =
        hex"01551220b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9";
    string public constant SAMPLE_CID_STRING =
        "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";
    string public constant SAMPLE_MANIFEST =
        "ipfs://bafybeiemxf5abjwjbikoz4mc3a3dla6ual3jsgpdr4cjr3oz3jfyebmt6u";
    string public constant SAMPLE_MANIFEST_CID_STRING =
        "bafybeiemxf5abjwjbikoz4mc3a3dla6ual3jsgpdr4cjr3oz3jfyebmt6u";

    string public constant SAMPLE_MIME_TYPE = "image/png";
    string public constant SAMPLE_LICENCE_CID =
        "bafybeihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku";
    bytes32 public constant SAMPLE_MANIFEST_CONTENT_HASH =
        keccak256("sample manifest content hash");

    bytes  public constant SAMPLE_DERIV_CID =
        hex"015512209b71d224bd62f3785d96d996a7a38d0b5b12321ab5a95d6e8c3c1e4e5f6a7b8c";
    string public constant SAMPLE_DERIV_ROLE = "exhibition-copy";

    // Custom error used by our onlyRole modifier
    error Unauthorised();

    // ─── Helper: mint a token with default test params ───────────────────

    function _mint(address to) internal returns (uint256 tokenId) {
        vm.prank(minter);
        tokenId = nft.mint(
            to,
            SAMPLE_CID_BYTES,
            SAMPLE_CID_STRING,
            SAMPLE_MANIFEST_CID_STRING,
            SAMPLE_MANIFEST,
            SAMPLE_MIME_TYPE,
            SAMPLE_LICENCE_CID,
            SAMPLE_MANIFEST_CONTENT_HASH
        );
    }

    function setUp() public {
        // Deploy as `admin` — that address becomes the owner (DEFAULT_ADMIN_ROLE)
        vm.prank(admin);
        nft = new NFTIntegrity(
            "TestNFT",
            "TEST",
            minter,
            manifestUpd,
            derivativeMgr
        );
    }

    // ─── Deployment & Roles ──────────────────────────────────────────────

    function testConstructorSetsRoles() public {
        assertTrue(nft.hasRole(nft.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(nft.hasRole(nft.MINTER_ROLE(), minter));
        assertTrue(nft.hasRole(nft.MANIFEST_UPDATER_ROLE(), manifestUpd));
        assertTrue(nft.hasRole(nft.DERIVATIVE_MANAGER_ROLE(), derivativeMgr));
        assertFalse(nft.hasRole(nft.MINTER_ROLE(), user));
    }

    function testConstructorSetsOwner() public {
        assertEq(nft.owner(), admin);
    }

    function testConstructorSetsNameAndSymbol() public {
        assertEq(nft.name(), "TestNFT");
        assertEq(nft.symbol(), "TEST");
    }

    function testGrantRole() public {
        // Verify admin holds DEFAULT_ADMIN_ROLE before calling grantRole
        assertTrue(nft.hasRole(nft.DEFAULT_ADMIN_ROLE(), admin));

        bytes32 minterRole = nft.MINTER_ROLE();
        vm.prank(admin);
        nft.grantRole(minterRole, user);
        assertTrue(nft.hasRole(minterRole, user));
        assertFalse(nft.hasRole(minterRole, minter)); // overwritten
    }

    function testGrantRoleRevertsNotAdmin() public {
        // Verify user does NOT hold DEFAULT_ADMIN_ROLE
        assertFalse(nft.hasRole(nft.DEFAULT_ADMIN_ROLE(), user));

        bytes32 minterRole = nft.MINTER_ROLE();
        vm.prank(user);
        vm.expectRevert("NFTIntegrity: not authorised for this role");
        nft.grantRole(minterRole, user);
    }

    function testRevokeRole() public {
        // Verify admin holds DEFAULT_ADMIN_ROLE before revoking
        assertTrue(nft.hasRole(nft.DEFAULT_ADMIN_ROLE(), admin));

        bytes32 minterRole = nft.MINTER_ROLE();
        vm.prank(admin);
        nft.revokeRole(minterRole);
        assertFalse(nft.hasRole(minterRole, minter));
    }

    function testRenounceRole() public {
        // Verify minter holds MINTER_ROLE before renouncing
        bytes32 minterRole = nft.MINTER_ROLE();
        assertTrue(nft.hasRole(minterRole, minter));

        vm.prank(minter);
        nft.renounceRole(minterRole);
        assertFalse(nft.hasRole(minterRole, minter));
    }

    // ─── Minting ─────────────────────────────────────────────────────────

    function testMintSuccess() public {
        uint256 tokenId = _mint(user);

        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(tokenId), user);
    }

    function testMintRevertsIfNotMinter() public {
        vm.prank(user);
        vm.expectRevert("NFTIntegrity: not authorised for this role");
        nft.mint(user, SAMPLE_CID_BYTES, SAMPLE_CID_STRING, SAMPLE_MANIFEST_CID_STRING, SAMPLE_MANIFEST, SAMPLE_MIME_TYPE, SAMPLE_LICENCE_CID, SAMPLE_MANIFEST_CONTENT_HASH);
    }

    function testMintRevertsEmptyCID() public {
        vm.prank(minter);
        vm.expectRevert("NFTIntegrity: empty CID");
        nft.mint(user, "", SAMPLE_CID_STRING, SAMPLE_MANIFEST_CID_STRING, SAMPLE_MANIFEST, SAMPLE_MIME_TYPE, SAMPLE_LICENCE_CID, SAMPLE_MANIFEST_CONTENT_HASH);
    }

    function testMintRevertsEmptyCIDString() public {
        vm.prank(minter);
        vm.expectRevert("NFTIntegrity: empty CID string");
        nft.mint(user, SAMPLE_CID_BYTES, "", SAMPLE_MANIFEST_CID_STRING, SAMPLE_MANIFEST, SAMPLE_MIME_TYPE, SAMPLE_LICENCE_CID, SAMPLE_MANIFEST_CONTENT_HASH);
    }

    function testMintRevertsEmptyManifestCIDString() public {
        vm.prank(minter);
        vm.expectRevert("NFTIntegrity: empty manifest CID string");
        nft.mint(user, SAMPLE_CID_BYTES, SAMPLE_CID_STRING, "", SAMPLE_MANIFEST, SAMPLE_MIME_TYPE, SAMPLE_LICENCE_CID, SAMPLE_MANIFEST_CONTENT_HASH);
    }

    function testMintRevertsManifestURIMismatch() public {
        vm.prank(minter);
        vm.expectRevert("NFTIntegrity: manifest URI must match manifest CID");
        nft.mint(user, SAMPLE_CID_BYTES, SAMPLE_CID_STRING, SAMPLE_MANIFEST_CID_STRING, string.concat("ipfs://", SAMPLE_CID_STRING), SAMPLE_MIME_TYPE, SAMPLE_LICENCE_CID, SAMPLE_MANIFEST_CONTENT_HASH);
    }

    function testMintRevertsEmptyManifestContentHash() public {
        vm.prank(minter);
        vm.expectRevert("NFTIntegrity: empty manifest content hash");
        nft.mint(user, SAMPLE_CID_BYTES, SAMPLE_CID_STRING, SAMPLE_MANIFEST_CID_STRING, SAMPLE_MANIFEST, SAMPLE_MIME_TYPE, SAMPLE_LICENCE_CID, bytes32(0));
    }

    function testMintTokenURI() public {
        uint256 tokenId = _mint(user);

        assertEq(nft.tokenURI(tokenId), SAMPLE_MANIFEST);
    }

    // ─── Token Integrity ─────────────────────────────────────────────────

    function testTokenIntegrity() public {
        _mint(user);

        IIntegrityNFT.TokenIntegrity memory ti = nft.tokenIntegrity(1);
        assertEq(ti.canonicalCID, SAMPLE_CID_BYTES);
        assertEq(ti.canonicalCIDString, SAMPLE_CID_STRING);
        assertEq(ti.manifestCIDString, SAMPLE_MANIFEST_CID_STRING);
        assertEq(ti.manifestURI, SAMPLE_MANIFEST);
        assertEq(ti.mimeType, SAMPLE_MIME_TYPE);
        assertEq(ti.licenceCID, SAMPLE_LICENCE_CID);
        assertEq(ti.manifestContentHash, SAMPLE_MANIFEST_CONTENT_HASH);
        assertEq(ti.ipfsImportKey, "ipfsImport");
    }

    function testTokenIntegrityRevertsNonExistent() public {
        vm.expectRevert("NFTIntegrity: token does not exist");
        nft.tokenIntegrity(999);
    }

    function testVerifyCanonicalCIDTrue() public {
        _mint(user);

        assertTrue(nft.verifyCanonicalCID(1, SAMPLE_CID_BYTES));
    }

    function testVerifyCanonicalCIDFalse() public {
        _mint(user);

        assertFalse(nft.verifyCanonicalCID(1, hex"deadbeef"));
    }

    // ─── Manifest Management ─────────────────────────────────────────────

    function testUpdateManifestURI() public {
        _mint(user);

        string memory newMancid = "bafybeixxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
        string memory newURI = string.concat("ipfs://", newMancid);

        vm.prank(manifestUpd);
        nft.updateManifestURI(1, newMancid, newURI, SAMPLE_MANIFEST_CONTENT_HASH);

        IIntegrityNFT.TokenIntegrity memory ti = nft.tokenIntegrity(1);
        assertEq(ti.manifestURI, newURI);
        assertEq(ti.manifestContentHash, SAMPLE_MANIFEST_CONTENT_HASH);
        assertEq(nft.tokenURI(1), newURI);
    }

    function testUpdateManifestURIRevertsNotAuthorised() public {
        _mint(user);

        string memory newMancid = "bafybeixxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
        string memory newURI = string.concat("ipfs://", newMancid);

        vm.prank(user);
        vm.expectRevert("NFTIntegrity: not authorised for this role");
        nft.updateManifestURI(1, newMancid, newURI, SAMPLE_MANIFEST_CONTENT_HASH);
    }

    function testUpdateManifestURIRevertsCIDMismatch() public {
        _mint(user);

        // A URI whose CID doesn't match the supplied manifest CID string must revert.
        // Use SAMPLE_CID_STRING (same length, different content) to bypass the length check.
        vm.prank(manifestUpd);
        vm.expectRevert("NFTIntegrity: manifest CID must match supplied manifest CID");
        nft.updateManifestURI(1, SAMPLE_MANIFEST_CID_STRING, string.concat("ipfs://", SAMPLE_CID_STRING), SAMPLE_MANIFEST_CONTENT_HASH);
    }

    function testUpdateManifestURIRevertsEmptyContentHash() public {
        _mint(user);

        string memory newMancid = "bafybeixxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
        string memory newURI = string.concat("ipfs://", newMancid);

        vm.prank(manifestUpd);
        vm.expectRevert("NFTIntegrity: empty manifest content hash");
        nft.updateManifestURI(1, newMancid, newURI, bytes32(0));
    }

    // ─── Canonical CID Immutability (implicit) ───────────────────────────

    function testCanonicalCIDIsImmutable() public {
        _mint(user);

        // There is no setter for the CID — it's set once during mint.
        IIntegrityNFT.TokenIntegrity memory ti = nft.tokenIntegrity(1);
        assertEq(ti.canonicalCID, SAMPLE_CID_BYTES);

        // Even after manifest update, CID stays the same.
        vm.prank(manifestUpd);
        nft.updateManifestURI(1, SAMPLE_MANIFEST_CID_STRING, string.concat("ipfs://", SAMPLE_MANIFEST_CID_STRING), SAMPLE_MANIFEST_CONTENT_HASH);

        ti = nft.tokenIntegrity(1);
        assertEq(ti.canonicalCID, SAMPLE_CID_BYTES);
    }

    // ─── Derivatives ─────────────────────────────────────────────────────

    function testAuthoriseDerivative() public {
        _mint(user);

        vm.prank(derivativeMgr);
        nft.authoriseDerivative(1, SAMPLE_DERIV_CID, SAMPLE_DERIV_ROLE);

        assertTrue(nft.isAuthorisedDerivative(1, SAMPLE_DERIV_CID));
        assertEq(nft.derivativeCount(1), 1);

        IIntegrityNFT.Derivative memory d = nft.getDerivative(1, SAMPLE_DERIV_CID);
        assertEq(d.derivativeCID, SAMPLE_DERIV_CID);
        assertEq(d.role, SAMPLE_DERIV_ROLE);
        assertEq(d.authorisedBy, derivativeMgr);
        assertTrue(d.active);
    }

    function testAuthoriseDerivativeRevertsDuplicate() public {
        _mint(user);

        vm.startPrank(derivativeMgr);
        nft.authoriseDerivative(1, SAMPLE_DERIV_CID, SAMPLE_DERIV_ROLE);
        vm.expectRevert("NFTIntegrity: already authorised");
        nft.authoriseDerivative(1, SAMPLE_DERIV_CID, "other-role");
        vm.stopPrank();
    }

    function testRevokeDerivative() public {
        _mint(user);

        vm.startPrank(derivativeMgr);
        nft.authoriseDerivative(1, SAMPLE_DERIV_CID, SAMPLE_DERIV_ROLE);
        nft.revokeDerivative(1, SAMPLE_DERIV_CID);
        vm.stopPrank();

        assertFalse(nft.isAuthorisedDerivative(1, SAMPLE_DERIV_CID));
        assertEq(nft.derivativeCount(1), 0);

        // getDerivative on a revoked one should revert
        vm.expectRevert("NFTIntegrity: not an active derivative");
        nft.getDerivative(1, SAMPLE_DERIV_CID);
    }

    function testDerivativeEnumeration() public {
        _mint(user);

        bytes[] memory cids = new bytes[](3);
        cids[0] = hex"01";
        cids[1] = hex"02";
        cids[2] = hex"03";

        vm.startPrank(derivativeMgr);
        for (uint256 i = 0; i < cids.length; i++) {
            nft.authoriseDerivative(1, cids[i], "role");
        }
        vm.stopPrank();

        assertEq(nft.derivativeCount(1), 3);

        for (uint i = 0; i < 3; i++) {
            IIntegrityNFT.Derivative memory d = nft.derivativeAt(1, i);
            assertEq(d.derivativeCID, cids[i]);
            assertTrue(d.active);
        }
    }

    // ─── Retrieval Config ────────────────────────────────────────────────

    function testRetrievalConfigDefault() public {
        IIntegrityNFT.RetrievalConfig memory rc = nft.retrievalConfig();
        assertEq(rc.preferredGateway, "");
        assertEq(rc.fallbackGateways, "");
        assertEq(rc.mirrors.length, 0);
    }

    function testUpdateRetrievalConfig() public {
        string memory gw = "https://ipfs.io/ipfs/";
        string memory fb = '["https://dweb.link/ipfs/","https://cf-ipfs.com/ipfs/"]';
        string[] memory mirrors = new string[](2);
        mirrors[0] = "https://mirror1.example/file.png";
        mirrors[1] = "https://mirror2.example/file.png";

        vm.prank(admin);
        nft.updateRetrievalConfig(gw, fb, mirrors);

        IIntegrityNFT.RetrievalConfig memory rc = nft.retrievalConfig();
        assertEq(rc.preferredGateway, gw);
        assertEq(rc.fallbackGateways, fb);
        assertEq(rc.mirrors.length, 2);
        assertEq(rc.mirrors[0], mirrors[0]);
        assertEq(rc.mirrors[1], mirrors[1]);
    }

    function testUpdateRetrievalConfigRevertsNotOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        nft.updateRetrievalConfig("gw", "fb", new string[](0));
    }

    // ─── ERC-165 ─────────────────────────────────────────────────────────

    function testSupportsInterface() public {
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC721Metadata).interfaceId));
        assertTrue(nft.supportsInterface(type(IIntegrityNFT).interfaceId));
        assertFalse(nft.supportsInterface(0xFFFFFFFF));
    }

    // ─── Events ──────────────────────────────────────────────────────────

    function testEmitTokenIntegritySet() public {
        vm.expectEmit(true, true, true, true);
        emit IIntegrityNFT.TokenIntegritySet(
            1, SAMPLE_CID_BYTES, SAMPLE_CID_STRING, SAMPLE_MANIFEST_CID_STRING, SAMPLE_MANIFEST, SAMPLE_MIME_TYPE, SAMPLE_LICENCE_CID, SAMPLE_MANIFEST_CONTENT_HASH
        );

        vm.prank(minter);
        nft.mint(user, SAMPLE_CID_BYTES, SAMPLE_CID_STRING, SAMPLE_MANIFEST_CID_STRING, SAMPLE_MANIFEST, SAMPLE_MIME_TYPE, SAMPLE_LICENCE_CID, SAMPLE_MANIFEST_CONTENT_HASH);
    }

    function testEmitDerivativeAuthorised() public {
        _mint(user);

        vm.expectEmit(true, true, true, true);
        emit IIntegrityNFT.DerivativeAuthorised(
            1, SAMPLE_DERIV_CID, SAMPLE_DERIV_ROLE, derivativeMgr
        );

        vm.prank(derivativeMgr);
        nft.authoriseDerivative(1, SAMPLE_DERIV_CID, SAMPLE_DERIV_ROLE);
    }
}
