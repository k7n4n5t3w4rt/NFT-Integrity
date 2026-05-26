#!/usr/bin/env node

/**
 * mint.js — Build a cast send command to mint an NFTIntegrity token.
 *
 * Reads a manifest.json, decodes the canonical CID to raw bytes, computes
 * keccak256 of the manifest file content, and prints (or executes) a full
 * cast send invocation.
 *
 * Usage:
 *   node scripts/mint.js manifest.json \
 *     --to 0xRecipient \
 *     --contract 0xContractAddress \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     [--dry-run]
 *
 * All CID decoding and hashing is self-contained — no npm dependencies.
 */

const fs   = require("fs");
const path = require("path");

// ═══════════════════════════════════════════════════════════════════════════
//  Base32 decoding (RFC 4648 lowercase — used by IPFS for CIDv1)
// ═══════════════════════════════════════════════════════════════════════════

const BASE32_ALPHABET = "abcdefghijklmnopqrstuvwxyz234567";
const BASE32_MAP = Object.fromEntries(
  [...BASE32_ALPHABET].map((c, i) => [c, i])
);

/**
 * Decode a base32 (RFC 4648 lowercase) string into a Buffer.
 * No padding is required — IPFS CIDs omit padding.
 */
function base32Decode(str) {
  str = str.toLowerCase().replace(/=+$/, "");
  if (!/^[a-z2-7]+$/.test(str)) {
    throw new Error("Invalid base32 string: " + str.slice(0, 20) + "...");
  }

  let bits = 0;
  let value = 0;
  const out = [];

  for (let i = 0; i < str.length; i++) {
    value = (value << 5) | BASE32_MAP[str[i]];
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }

  // Any remaining partial-byte bits should be zero (valid encoding)
  if (bits > 0 && (value & ((1 << bits) - 1)) !== 0) {
    throw new Error("Base32: non-zero trailing bits");
  }

  return Buffer.from(out);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Base58btc decoding (used by IPFS for CIDv0)
// ═══════════════════════════════════════════════════════════════════════════

const BASE58_ALPHABET =
  "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const BASE58_MAP = Object.fromEntries(
  [...BASE58_ALPHABET].map((c, i) => [c, i])
);

function base58btcDecode(str) {
  // Build big-endian bytes via base-58 conversion
  const bytes = [];
  for (let i = 0; i < str.length; i++) {
    let carry = BASE58_MAP[str[i]];
    if (carry === undefined) {
      throw new Error("Invalid base58 character: " + str[i]);
    }
    for (let j = 0; j < bytes.length; j++) {
      carry += bytes[j] * 58;
      bytes[j] = carry & 0xff;
      carry >>= 8;
    }
    while (carry > 0) {
      bytes.push(carry & 0xff);
      carry >>= 8;
    }
  }

  // Handle leading '1' characters (each represents a zero byte)
  for (let i = 0; i < str.length && str[i] === "1"; i++) {
    bytes.push(0);
  }

  return Buffer.from(bytes.reverse());
}

// ═══════════════════════════════════════════════════════════════════════════
//  CID → raw bytes  (self-contained — no multiformats dependency)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Decode an IPFS CID string to its raw binary representation.
 *
 * CIDv1 in base32:   starts with 'b' (multibase), then base32 data.
 * CIDv0 in base58btc: starts with 'Qm', entire string is base58.
 * CIDv1 in base16:   starts with 'f' (multibase), then hex data.
 * CIDv1 in base58btc: starts with 'z' (multibase), then base58 data.
 */
function cidToBytes(cidStr) {
  const first = cidStr[0];

  // CIDv1 base32 — most common (e.g. bafybei…)
  if (first === "b" || first === "B") {
    return base32Decode(cidStr.slice(1));
  }

  // CIDv1 base16 (e.g. f01551220…)
  if (first === "f" || first === "F") {
    return Buffer.from(cidStr.slice(1), "hex");
  }

  // CIDv0 base58btc (e.g. Qm…)
  if (first === "Q") {
    return base58btcDecode(cidStr);
  }

  // CIDv1 base58btc (e.g. z…)
  if (first === "z" || first === "Z") {
    return base58btcDecode(cidStr.slice(1));
  }

  // Fallback: try as raw hex
  if (/^[0-9a-fA-F]+$/.test(cidStr)) {
    return Buffer.from(cidStr, "hex");
  }

  // Last resort: try base58btc on the whole string
  return base58btcDecode(cidStr);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Keccak-256  (pure JS, zero dependencies — Ethereum's original Keccak)
// ═══════════════════════════════════════════════════════════════════════════
//
//  Based on the Keccak specification (FIPS 202 / Keccak team reference).
//  This is the original Keccak-256 used by Ethereum, NOT SHA3-256
//  (which differs in the domain-separator padding byte).
//
//  Bit-width guard: JavaScript BigInts have arbitrary precision, but the
//  Keccak permutation operates on 64-bit lanes.  Every operation that can
//  produce a value wider than 64 bits is explicitly masked with & M64.

/* eslint-disable */

const M64           = (1n << 64n) - 1n;
const KECCAK_ROUNDS = 24;
const KECCAK_RC = [
  0x0000000000000001n, 0x0000000000008082n, 0x800000000000808an,
  0x8000000080008000n, 0x000000000000808bn, 0x0000000080000001n,
  0x8000000080008081n, 0x8000000000008009n, 0x000000000000008an,
  0x0000000000000088n, 0x0000000080008009n, 0x000000008000000an,
  0x000000008000808bn, 0x800000000000008bn, 0x8000000000008089n,
  0x8000000000008003n, 0x8000000000008002n, 0x8000000000000080n,
  0x000000000000800an, 0x800000008000000an, 0x8000000080008081n,
  0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n,
];

// Rotation offsets for ρ step, indexed by lane (x + 5·y)
const ROT = [
   0,  1, 62, 28, 27,
  36, 44,  6, 55, 20,
   3, 10, 43, 25, 39,
  41, 45, 15, 21,  8,
  18,  2, 61, 56, 14,
];

/** 64-bit left rotation with explicit mask. */
function rotl64(v, r) {
  return ((v << BigInt(r)) | (v >> BigInt(64 - r))) & M64;
}

/** Keccak-f[1600] permutation (24 rounds).  Mutates `st` in-place. */
function keccakF(st) {
  for (let round = 0; round < KECCAK_ROUNDS; round++) {
    // ── Theta ──────────────────────────────────────────────────────
    const C = new Array(5);
    for (let x = 0; x < 5; x++) {
      C[x] = st[x] ^ st[x + 5] ^ st[x + 10] ^ st[x + 15] ^ st[x + 20];
    }
    for (let x = 0; x < 5; x++) {
      const D = C[(x + 4) % 5] ^ rotl64(C[(x + 1) % 5], 1);
      for (let y = 0; y < 5; y++) {
        st[x + 5 * y] ^= D;
      }
    }

    // ── Rho + Pi ───────────────────────────────────────────────────
    const B = new Array(25).fill(0n);
    for (let x = 0; x < 5; x++) {
      for (let y = 0; y < 5; y++) {
        const idx = x + 5 * y;
        // Pi: (x, y) → (y, (2x + 3y) % 5)   after applying Rho rotation
        B[y + 5 * ((2 * x + 3 * y) % 5)] = rotl64(st[idx], ROT[idx]);
      }
    }

    // ── Chi ────────────────────────────────────────────────────────
    // Operates on adjacent columns (x+1, x+2) for each row y.
    // ~t is bitwise-NOT; & M64 keeps the result within 64 bits.
    for (let x = 0; x < 5; x++) {
      for (let y = 0; y < 5; y++) {
        const t = B[((x + 1) % 5) + 5 * y];
        const u = B[((x + 2) % 5) + 5 * y];
        st[x + 5 * y] = B[x + 5 * y] ^ ((~t & u) & M64);
      }
    }

    // ── Iota ───────────────────────────────────────────────────────
    st[0] ^= KECCAK_RC[round];
  }
}

/**
 * Keccak-256 hash of a Buffer or string.
 *
 * Rate = 1088 bits = 136 bytes.  Absorbs full blocks, then pads the
 * final block with Keccak domain padding (0x01 ‖ 10*1).
 */
function keccak256(data) {
  const buf  = Buffer.isBuffer(data) ? data : Buffer.from(data);
  const rate = 136;                       // bytes
  const len  = buf.length;

  const state = new Array(25).fill(0n);

  // ── Absorb full blocks ──────────────────────────────────────────
  let offset = 0;
  while (offset + rate <= len) {
    for (let i = 0; i < rate / 8; i++) {
      const base = offset + i * 8;
      let w = 0n;
      for (let b = 0; b < 8; b++) {
        w |= BigInt(buf[base + b]) << BigInt(b * 8);
      }
      state[i] ^= w;
    }
    keccakF(state);
    offset += rate;
  }

  // ── Pad & absorb final block ────────────────────────────────────
  const remaining  = len - offset;
  const finalBlock = Buffer.alloc(rate);
  buf.copy(finalBlock, 0, offset, len);
  finalBlock[remaining]    = 0x01;   // Keccak domain separator
  finalBlock[rate - 1]    |= 0x80;   // final bit of 10*1 padding

  for (let i = 0; i < rate / 8; i++) {
    let w = 0n;
    for (let b = 0; b < 8; b++) {
      w |= BigInt(finalBlock[i * 8 + b]) << BigInt(b * 8);
    }
    state[i] ^= w;
  }
  keccakF(state);

  // ── Squeeze 32 bytes (256 bits) ─────────────────────────────────
  const digest = Buffer.alloc(32);
  for (let i = 0; i < 4; i++) {
    let w = state[i];
    for (let b = 0; b < 8; b++) {
      digest[i * 8 + b] = Number(w & 0xffn);
      w >>= 8n;
    }
  }

  return digest;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Argument parsing
// ═══════════════════════════════════════════════════════════════════════════

function parseArgs(argv) {
  const args = {};
  const positional = [];
  for (let i = 2; i < argv.length; i++) {
    if (argv[i].startsWith("--")) {
      const key = argv[i].slice(2);
      const val =
        argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[++i] : "true";
      args[key] = val;
    } else if (!argv[i].startsWith("-")) {
      positional.push(argv[i]);
    }
  }
  return { args, positional };
}

function printHelp() {
  console.log(`Usage: node scripts/mint.js <manifest.json> [OPTIONS]

Required arguments:
  --to             ADDRESS   Recipient address (0x…)
  --contract       ADDRESS   NFTIntegrity contract address (0x…)
  --rpc-url        URL       Ethereum RPC endpoint
  --private-key    KEY       Private key for signing

Flags:
  --dry-run                  Print the cast send command without executing

Extracted from manifest.json:
  • canonical CID   (canonicalMedia.cid)    → decoded to raw bytes
  • MIME type       (canonicalMedia.mimeType)
  • licence CID     (rights.licenceCID)
  • manifest CID    derived from the canonical CID via the manifest content
  • manifest content hash (keccak256 of the raw manifest file bytes)

Example:
  node scripts/mint.js manifest.json \\
    --to 0xRecipientAddress \\
    --contract \$CONTRACT_ADDRESS \\
    --rpc-url \$RPC_URL \\
    --private-key \$PRIVATE_KEY \\
    --dry-run

The script prints the full cast send command.
Remove --dry-run to execute it via cast.
`);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Main
// ═══════════════════════════════════════════════════════════════════════════

function main() {
  const { args, positional } = parseArgs(process.argv);

  if (args.help || args.h) {
    printHelp();
    process.exit(0);
  }

  // Manifest file path
  const manifestPath = positional[0];
  if (!manifestPath) {
    console.error(
      "Error: manifest.json path is required.  Use --help for usage."
    );
    process.exit(1);
  }
  if (!fs.existsSync(manifestPath)) {
    console.error("Error: file not found: " + manifestPath);
    process.exit(1);
  }

  // Required flags
  const required = ["to", "contract", "rpc-url", "private-key"];
  const missing  = required.filter((k) => !args[k]);
  if (missing.length > 0) {
    console.error(
      "Error: missing required arguments: " +
        missing.map((k) => "--" + k).join(", ") +
        "\nUse --help for usage."
    );
    process.exit(1);
  }

  const dryRun = args["dry-run"] !== undefined;

  // ── Read manifest ──────────────────────────────────────────────────

  const manifestRaw = fs.readFileSync(manifestPath);
  let manifest;
  try {
    manifest = JSON.parse(manifestRaw.toString("utf-8"));
  } catch (e) {
    console.error(
      "Error: failed to parse " + manifestPath + " as JSON: " + e.message
    );
    process.exit(1);
  }

  // Extract fields
  const canonicalCIDString = manifest.canonicalMedia?.cid;
  const mimeType           = manifest.canonicalMedia?.mimeType;
  const licenceCID         = manifest.rights?.licenceCID;

  if (!canonicalCIDString) {
    console.error("Error: manifest is missing canonicalMedia.cid");
    process.exit(1);
  }
  if (!mimeType) {
    console.error("Error: manifest is missing canonicalMedia.mimeType");
    process.exit(1);
  }
  if (!licenceCID) {
    console.error("Error: manifest is missing rights.licenceCID");
    process.exit(1);
  }

  // Derive the manifest CID: the canonicalMedia.cid identifies the media
  // file; the manifest is a separate file with its own CID.  We infer it
  // from the manifestURI if present, otherwise use a sensible default.
  let manifestCIDString;
  if (manifest.retrieval?.manifestURI) {
    // manifest.retrieval.manifestURI is e.g. "ipfs://bafy..."
    const m = manifest.retrieval.manifestURI.match(
      /^ipfs:\/\/([a-zA-Z2-7]+)$/
    );
    if (m) {
      manifestCIDString = m[1];
    }
  }
  if (!manifestCIDString) {
    // Fallback: if the manifest was also added to IPFS, the user can
    // provide it via --manifest-cid (backward compat) or it can be
    // passed as an env/arg.
    manifestCIDString = args["manifest-cid"];
  }
  if (!manifestCIDString) {
    console.error(
      "Error: could not determine manifest CID.\n" +
        "  Either set retrieval.manifestURI in the manifest, or pass --manifest-cid explicitly."
    );
    process.exit(1);
  }

  const manifestURI = "ipfs://" + manifestCIDString;

  // ── Decode CID to raw bytes ────────────────────────────────────────

  let canonicalCIDHex;
  try {
    canonicalCIDHex = "0x" + cidToBytes(canonicalCIDString).toString("hex");
  } catch (e) {
    console.error(
      "Error: failed to decode canonical CID \"" +
        canonicalCIDString +
        "\": " +
        e.message
    );
    process.exit(1);
  }

  // ── Compute keccak256 of manifest file content ─────────────────────

  const manifestContentHash =
    "0x" + keccak256(manifestRaw).toString("hex");

  // ── Build cast send command ────────────────────────────────────────

  const cmd = [
    "cast send",
    escapeArg(args["contract"]),
    escapeArg("mint(address,bytes,string,string,string,string,string,bytes32)"),
    escapeArg(args["to"]),
    escapeArg(canonicalCIDHex),
    escapeArg(canonicalCIDString),
    escapeArg(manifestCIDString),
    escapeArg(manifestURI),
    escapeArg(mimeType),
    escapeArg(licenceCID),
    escapeArg(manifestContentHash),
    "--private-key",
    args["private-key"],
    "--rpc-url",
    args["rpc-url"],
  ].join(" ");

  console.log(cmd);

  if (!dryRun) {
    console.error("Executing…");
    const { execSync } = require("child_process");
    try {
      execSync(cmd, { stdio: "inherit", encoding: "utf-8" });
    } catch (e) {
      console.error(
        "cast send failed.  Check your RPC, private key, and that the sender has MINTER_ROLE."
      );
      process.exit(1);
    }
  } else {
    console.error("(dry-run — command printed but not executed)");
  }
}

// ── Shell-escaping helpers ──────────────────────────────────────────────

function escapeArg(arg) {
  // Only quote if the arg contains spaces or special shell characters
  if (/[\s"'$`\\|&;<>(){}*?!\[\]~#]/.test(arg) || arg === "") {
    // Use single quotes, escaping any embedded single quotes
    return "'" + arg.replace(/'/g, "'\\''") + "'";
  }
  return arg;
}

// ── Run ─────────────────────────────────────────────────────────────────

main();
