#!/usr/bin/env node
/**
 * Strip CI gate: verify Experience Ed25519 receipt fixtures.
 *
 * Optional: set ZIG_RECEIPT to a path of a Zig-emitted receipt.json to also
 * verify with the Experience JS verifier (interop check).
 */
import { readFileSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  verifyReceiptFieldPresence,
  verifyReceiptEd25519,
  hexToBytes,
} from "./lib/receipt.js";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const fix = (...p) => resolve(root, "fixtures/experience-receipt", ...p);

const errors = [];

const field = JSON.parse(readFileSync(fix("uas-receipt.json"), "utf8"));
const fieldCheck = verifyReceiptFieldPresence(field);
if (!fieldCheck.ok) errors.push(`field-presence: ${fieldCheck.errors.join("; ")}`);

const signed = JSON.parse(readFileSync(fix("uas-receipt-ed25519.json"), "utf8"));
const key = JSON.parse(readFileSync(fix("ed25519-dev-key.json"), "utf8"));
const cryptoCheck = verifyReceiptEd25519(signed, hexToBytes(key.public_key_hex));
if (!cryptoCheck.ok) errors.push(`ed25519: ${cryptoCheck.errors.join("; ")}`);

const tampered = structuredClone(signed);
tampered.events_sha256 = "0".repeat(64);
const bad = verifyReceiptEd25519(tampered, hexToBytes(key.public_key_hex));
if (bad.ok) errors.push("tampered receipt incorrectly verified");

let zigCheck = null;
const zigPathEnv = process.env.ZIG_RECEIPT;
if (zigPathEnv) {
  const zigPath = resolve(zigPathEnv);
  if (!existsSync(zigPath)) {
    errors.push(`ZIG_RECEIPT not found: ${zigPath}`);
  } else {
    const zigReceipt = JSON.parse(readFileSync(zigPath, "utf8"));
    const zigField = verifyReceiptFieldPresence(zigReceipt);
    if (!zigField.ok) errors.push(`zig field-presence: ${zigField.errors.join("; ")}`);
    const zigCrypto = verifyReceiptEd25519(zigReceipt);
    if (!zigCrypto.ok) errors.push(`zig ed25519: ${zigCrypto.errors.join("; ")}`);
    zigCheck = {
      path: zigPath,
      field_ok: zigField.ok,
      ed25519_ok: zigCrypto.ok,
      public_key_id: zigReceipt.signature?.public_key_id,
    };
  }
}

const out = {
  workflow: "strip-experience-receipt-crypto",
  passed: errors.length === 0,
  field_presence: { ok: fieldCheck.ok },
  ed25519: {
    ok: cryptoCheck.ok,
    public_key_id: signed.signature?.public_key_id,
    tamper_rejected: !bad.ok,
  },
  zig_receipt: zigCheck,
  useful_for: "Strip CI enforces Experience AF crypto receipt fixture + optional Zig emit verify",
  not_claimed: [
    "HSM custody",
    "flight clearance",
    "operational qualification",
  ],
  operational_qualification_claimed: false,
};

if (errors.length) {
  for (const e of errors) console.error("FAIL:", e);
  console.log(JSON.stringify(out, null, 2));
  process.exit(1);
}
console.log(JSON.stringify(out, null, 2));
