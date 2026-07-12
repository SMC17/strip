/**
 * Receipt verification ports — field-presence and Ed25519.
 */
import { ed25519 } from "@noble/curves/ed25519.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { bytesToHex, hexToBytes } from "@noble/hashes/utils.js";

export const RECEIPT_SCHEMA = "strip.trajectory.receipt.v0";

function sortKeys(value) {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((k) => [k, sortKeys(value[k])]),
    );
  }
  return value;
}

function canonicalPayload(receipt) {
  const { signature, ...rest } = receipt;
  return JSON.stringify(sortKeys(rest));
}

function payloadHash(receipt) {
  return sha256(new TextEncoder().encode(canonicalPayload(receipt)));
}

/**
 * @param {object} receipt
 */
export function verifyReceiptFieldPresence(receipt) {
  const errors = [];
  if (!receipt || typeof receipt !== "object") {
    return { ok: false, cryptographic: false, errors: ["receipt missing"] };
  }
  if (receipt.schema && receipt.schema !== RECEIPT_SCHEMA) {
    errors.push(`unexpected receipt schema ${receipt.schema}`);
  }
  if (receipt.operational_qualification_claimed !== false) {
    errors.push("operational_qualification_claimed must be false");
  }
  const mode = receipt.verification_mode || "field-presence-only";
  if (mode === "ed25519") {
    // field presence still required; crypto checked separately
  } else if (mode !== "field-presence-only") {
    errors.push(`unsupported verification_mode ${mode}`);
  }
  if (mode === "field-presence-only" && receipt.cryptographic_proof === true) {
    errors.push("cryptographic_proof=true requires verification_mode=ed25519");
  }
  if (!receipt.trajectory_id) errors.push("missing trajectory_id");
  const sig = receipt.signature || {};
  if (!sig.algorithm) errors.push("signature.algorithm missing");
  if (!sig.public_key_id) errors.push("signature.public_key_id missing");
  if (mode === "field-presence-only" && sig.status === "verified") {
    errors.push("signature.status=verified is forbidden without ed25519 verify");
  }
  return {
    ok: errors.length === 0,
    cryptographic: false,
    errors,
    public_key_id: sig.public_key_id,
    mode,
  };
}

/**
 * @param {Uint8Array} privateKey 32 bytes
 * @param {object} receiptBody receipt without signature
 * @param {string} publicKeyId
 */
export function signReceiptEd25519(secretKey, receiptBody, publicKeyId) {
  const draft = {
    ...receiptBody,
    verification_mode: "ed25519",
    cryptographic_proof: true,
    operational_qualification_claimed: false,
  };
  const hash = payloadHash(draft);
  const sig = ed25519.sign(hash, secretKey);
  const pub = ed25519.getPublicKey(secretKey);
  return {
    ...draft,
    signature: {
      algorithm: "ed25519",
      public_key_id: publicKeyId,
      public_key_hex: bytesToHex(pub),
      value_hex: bytesToHex(sig),
      payload_sha256_hex: bytesToHex(hash),
      status: "signed",
    },
  };
}

/**
 * @param {object} receipt
 * @param {Uint8Array} [publicKey] optional override; else uses signature.public_key_hex
 */
export function verifyReceiptEd25519(receipt, publicKey) {
  const field = verifyReceiptFieldPresence({
    ...receipt,
    verification_mode: receipt.verification_mode || "ed25519",
  });
  const errors = [...field.errors];
  if (receipt.verification_mode !== "ed25519") {
    errors.push("verification_mode must be ed25519");
  }
  if (receipt.cryptographic_proof !== true) {
    errors.push("cryptographic_proof must be true for ed25519 mode");
  }
  const sig = receipt.signature || {};
  if (sig.algorithm !== "ed25519") errors.push("signature.algorithm must be ed25519");
  if (!sig.value_hex) errors.push("signature.value_hex missing");
  if (!sig.public_key_hex && !publicKey) errors.push("public key missing");

  if (errors.length) {
    return { ok: false, cryptographic: true, errors, mode: "ed25519" };
  }

  const pub = publicKey || hexToBytes(sig.public_key_hex);
  const hash = payloadHash(receipt);
  if (sig.payload_sha256_hex && sig.payload_sha256_hex !== bytesToHex(hash)) {
    return {
      ok: false,
      cryptographic: true,
      errors: ["payload hash mismatch"],
      mode: "ed25519",
    };
  }
  const ok = ed25519.verify(hexToBytes(sig.value_hex), hash, pub);
  return {
    ok,
    cryptographic: true,
    errors: ok ? [] : ["ed25519 signature invalid"],
    mode: "ed25519",
    public_key_id: sig.public_key_id,
  };
}

export function generateEd25519KeyPair() {
  const { secretKey, publicKey } = ed25519.keygen();
  return {
    secretKey,
    publicKey,
    privateKey: secretKey,
    private_key_hex: bytesToHex(secretKey),
    public_key_hex: bytesToHex(publicKey),
  };
}

export { bytesToHex, hexToBytes };
