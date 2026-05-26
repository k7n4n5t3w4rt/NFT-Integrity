#!/usr/bin/env node

/**
 * create-manifest.js — Create an NFT Integrity Manifest (v1).
 *
 * All CID-affecting import parameters are required and have no defaults.
 * This ensures the manifest accurately captures the exact recipe used to
 * produce the canonical CID — no parameter is ever assumed or guessed.
 */

const fs = require("fs");
const path = require("path");

// ─── Defaults ────────────────────────────────────────────────────────────

const DEFAULTS = {
  schema: "https://example.org/nft-integrity-manifest/v1",

  token: {
    standard: "ERC-721",
    contract: "0xCONTRACT_ADDRESS",
    tokenId: "1",
    tokenURI: null, // derived from CID
  },

  work: {
    title: "Untitled",
    artist: "Unknown",
    created: new Date().toISOString().slice(0, 10),
    description: "",
  },

  ipfsImport: {
    implementation: "kubo",
    implementationVersion: "0.29.0",
    // CID-affecting — no defaults; must be explicitly provided
    cidVersion: null,
    hashFunction: null,
    codec: null,
    unixfs: null,
    rawLeaves: null,
    chunker: null,
    wrapWithDirectory: null,
    inline: null,
    // Non-CID-affecting helpers
    pin: true,
    nocopy: false,
    cidBase: "base32",
  },

  retrieval: {
    preferredGateway: "https://ipfs.io/ipfs/",
    fallbackGateways: [
      "https://dweb.link/ipfs/",
      "https://cloudflare-ipfs.com/ipfs/",
      "https://gateway.pinata.cloud/ipfs/",
    ],
    mirrors: [],
  },

  rights: {
    licenceURI: "ipfs://PLACEHOLDER_LICENCE_CID",
    licenceCID: "PLACEHOLDER_LICENCE_CID",
    summary:
      "Token ownership does not imply copyright transfer except as specified in the licence.",
  },

  governance: {
    gatewayUpdates: {
      allowedBy: "DEFAULT_ADMIN_ROLE",
      rule: "Gateways may be updated without changing canonical media identity.",
    },
    mirrorUpdates: {
      allowedBy: "DEFAULT_ADMIN_ROLE",
      rule: "New mirrors must reproduce the canonical CID using the specified IPFS import settings.",
    },
    canonicalMediaUpdates: {
      allowedBy: "not-allowed",
      rule: "The canonical media CID is immutable.",
    },
    derivativeApprovals: {
      allowedBy: "DERIVATIVE_MANAGER_ROLE",
      rule: "Any file producing a different CID must be recorded as an authorised derivative, not substituted for the canonical artefact.",
    },
  },

  canonicalMedia: {
    role: "canonical",
    uri: null,
    cid: null,
    mimeType: null,
    integrityRule:
      "A retrieved file is valid as the canonical artefact only if it resolves to the canonical IPFS CID when imported using the specified IPFS import settings.",
  },

  authorisedDerivatives: [],
};

// ─── Argument parsing (simple argv walker) ───────────────────────────────

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    if (argv[i].startsWith("--")) {
      const key = argv[i].slice(2);
      const val = argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : "true";
      args[key] = val;
    }
  }
  return args;
}

function setNested(obj, path, value) {
  const keys = path.split(".");
  let cur = obj;
  for (let i = 0; i < keys.length - 1; i++) {
    if (!cur[keys[i]]) cur[keys[i]] = {};
    cur = cur[keys[i]];
  }
  // Coerce booleans and numbers
  if (value === "true") value = true;
  else if (value === "false") value = false;
  else if (/^\d+$/.test(value)) value = parseInt(value, 10);
  cur[keys[keys.length - 1]] = value;
}

// ─── Main ────────────────────────────────────────────────────────────────

function main() {
  const args = parseArgs(process.argv);

  if (args.help || args.h) {
    console.log(`Usage: node scripts/create-manifest.js [OPTIONS]

Required:
  --cid                        CID     IPFS CID of the canonical artefact
  --mime                       TYPE    MIME type (e.g. image/png, video/mp4)

Required CID-affecting import parameters (must match the flags used with ipfs add):
  --ipfsImport.cidVersion      NUM     CID version (0 or 1)
  --ipfsImport.hashFunction    STR     Multihash function (e.g. sha2-256)
  --ipfsImport.codec           STR     IPLD codec (e.g. dag-pb, raw)
  --ipfsImport.chunker         STR     Chunking strategy (e.g. size-262144)
  --ipfsImport.rawLeaves       BOOL    Raw leaves (true or false)
  --ipfsImport.unixfs          BOOL    UnixFS wrapping (true or false)
  --ipfsImport.wrapWithDirectory BOOL  Wrap in directory (true or false)
  --ipfsImport.inline          BOOL    Inline small blocks (true or false)

Recommended:
  --title     STR     Title of the work
  --artist    STR     Artist name
  --contract  ADDR    Contract address (0x...)
  --tokenId   NUM     Token ID
  --licence   CID     CID of the licence document
  --tokenURI  URI     Token URI (known only after manifest is uploaded to IPFS)

Optional overrides (dot-separated path):
  --ipfsImport.implementation     STR   (default: kubo)
  --ipfsImport.implementationVersion STR
  --retrieval.preferredGateway    URI
  --retrieval.fallbackGateways    JSON array string
  --governance.canonicalMediaUpdates.allowedBy STR
  --derivatives JSON              JSON array of derivative objects
  --output     PATH               Output file (default: stdout)

Example:
  node scripts/create-manifest.js \\
    --cid bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi \\
    --mime image/png \\
    --ipfsImport.cidVersion 1 \\
    --ipfsImport.hashFunction sha2-256 \\
    --ipfsImport.codec dag-pb \\
    --ipfsImport.chunker size-262144 \\
    --ipfsImport.rawLeaves true \\
    --ipfsImport.unixfs true \\
    --ipfsImport.wrapWithDirectory false \\
    --ipfsImport.inline false \\
    --title "My Work" \\
    --artist "Jane Doe" \\
    --contract 0x1234567890123456789012345678901234567890 \\
    --tokenId 1 \\
    --output manifest.json
`);
    process.exit(0);
  }

  if (!args.cid || !args.mime) {
    console.error("Error: --cid and --mime are required. Use --help for usage.");
    process.exit(1);
  }

  // CID-affecting import params — all required (no defaults)
  const CID_PARAMS = [
    "ipfsImport.cidVersion",
    "ipfsImport.hashFunction",
    "ipfsImport.codec",
    "ipfsImport.chunker",
    "ipfsImport.rawLeaves",
    "ipfsImport.unixfs",
    "ipfsImport.wrapWithDirectory",
    "ipfsImport.inline",
  ];
  const missing = CID_PARAMS.filter(p => args[p] === undefined);
  if (missing.length > 0) {
    console.error(
      `Error: Missing required CID-affecting import parameters:\n  ${missing.map(p => `--${p}`).join("\n  ")}\n\nUse --help for usage.`
    );
    process.exit(1);
  }

  // Coerce boolean CID params properly
  for (const p of ["ipfsImport.rawLeaves", "ipfsImport.unixfs", "ipfsImport.wrapWithDirectory", "ipfsImport.inline"]) {
    if (args[p] !== undefined) {
      if (args[p] === "true" || args[p] === true) args[p] = true;
      else if (args[p] === "false" || args[p] === false) args[p] = false;
      else {
        console.error(`Error: --${p} must be "true" or "false", got "${args[p]}".`);
        process.exit(1);
      }
    }
  }

  // Deep-clone defaults
  const manifest = JSON.parse(JSON.stringify(DEFAULTS));

  // Set work fields
  if (args.title) manifest.work.title = args.title;
  if (args.artist) manifest.work.artist = args.artist;
  if (args.description) manifest.work.description = args.description;
  if (args.created) manifest.work.created = args.created;

  // Set token
  if (args.contract) manifest.token.contract = args.contract;
  if (args.tokenId) manifest.token.tokenId = args.tokenId;

  // Set canonical media
  manifest.canonicalMedia.cid = args.cid;
  manifest.canonicalMedia.uri = `ipfs://${args.cid}`;
  manifest.canonicalMedia.mimeType = args.mime;

  // Set tokenURI (only when known — typically after manifest is uploaded to IPFS)
  if (args.tokenURI) manifest.token.tokenURI = args.tokenURI;

  // Set licence
  if (args.licence) {
    manifest.rights.licenceCID = args.licence;
    manifest.rights.licenceURI = `ipfs://${args.licence}`;
  }

  // Deep overrides via dot-path args
  for (const [key, value] of Object.entries(args)) {
    if (key.includes(".")) {
      setNested(manifest, key, value);
    }
  }

  // Derivatives from JSON string
  if (args.derivatives) {
    try {
      manifest.authorisedDerivatives = JSON.parse(args.derivatives);
    } catch {
      console.error("Error: --derivatives must be valid JSON array.");
      process.exit(1);
    }
  }

  // Fallback gateways from JSON string
  if (args["retrieval.fallbackGateways"]) {
    try {
      manifest.retrieval.fallbackGateways = JSON.parse(
        args["retrieval.fallbackGateways"]
      );
    } catch {
      console.error(
        "Error: --retrieval.fallbackGateways must be valid JSON array."
      );
      process.exit(1);
    }
  }

  const json = JSON.stringify(manifest, null, 2);

  if (args.output) {
    fs.writeFileSync(args.output, json, "utf-8");
    console.log(`Manifest written to ${args.output}`);
  } else {
    console.log(json);
  }
}

main();
