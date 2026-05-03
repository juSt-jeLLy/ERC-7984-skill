#!/usr/bin/env node
/**
 * validate-skill.mjs
 *
 * Structural validator for the zama-fhevm-skill package.
 * Verifies all required files exist and key sections are present in SKILL.md.
 *
 * Usage:
 *   node scripts/validate-skill.mjs
 *   node scripts/validate-skill.mjs --strict   (exits 1 on warnings too)
 */

import { readFileSync, existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dir = dirname(fileURLToPath(import.meta.url));
const root = join(__dir, "..");
const strict = process.argv.includes("--strict");

let errors = 0;
let warnings = 0;

function pass(msg) {
  console.log(`  ✅  ${msg}`);
}

function warn(msg) {
  console.warn(`  ⚠️   ${msg}`);
  warnings++;
}

function fail(msg) {
  console.error(`  ❌  ${msg}`);
  errors++;
}

function check(filePath, label) {
  const abs = join(root, filePath);
  if (existsSync(abs)) {
    pass(`${label ?? filePath}`);
    return true;
  } else {
    fail(`Missing: ${filePath}`);
    return false;
  }
}

function checkContent(filePath, patterns, label) {
  const abs = join(root, filePath);
  if (!existsSync(abs)) {
    fail(`Cannot check content — file missing: ${filePath}`);
    return;
  }
  const content = readFileSync(abs, "utf8");
  for (const { pattern, description } of patterns) {
    if (pattern.test(content)) {
      pass(`${label}: contains "${description}"`);
    } else {
      fail(`${label}: missing "${description}" in ${filePath}`);
    }
  }
}

// ─── Run validation ──────────────────────────────────────────────────────────

console.log("\n🔍  Validating zama-fhevm-skill structure…\n");

// Required root files
console.log("── Root files ──");
check("SKILL.md", "SKILL.md (main entry point)");
check("AGENTS.md", "AGENTS.md (Codex / plain-markdown adapter)");
check("README.md", "README.md");

// Cursor adapter
console.log("\n── Cursor adapter ──");
check(".cursor/rules/zama-fhevm.mdc", ".cursor/rules/zama-fhevm.mdc");

// Codex metadata
console.log("\n── Codex metadata ──");
check("agents/openai.yaml", "agents/openai.yaml");

// Validator
console.log("\n── Scripts ──");
check("scripts/validate-skill.mjs", "scripts/validate-skill.mjs");

// All reference files
const refs = [
  "architecture.md",
  "setup.md",
  "solidity-patterns.md",
  "encrypted-types.md",
  "fhe-operations.md",
  "access-control.md",
  "input-proofs.md",
  "decryption.md",
  "frontend-integration.md",
  "testing.md",
  "deployment.md",
  "oz-confidential.md",
  "error-reference.md",
  "anti-patterns.md",
  "addresses.md",
  "validation.md",
  "distribution.md",
];

console.log("\n── Reference files ──");
for (const ref of refs) {
  check(`references/${ref}`, `references/${ref}`);
}

// All example files
const examples = [
  "hardhat.config.ts",
  "ConfidentialCounter.sol",
  "ConfidentialToken.sol",
  "ConfidentialTokenFhevmContracts.sol",
  "ConfidentialVoting.sol",
  "ConfidentialAuction.sol",
  "frontend-integration.tsx",
  "test-example.ts",
];

console.log("\n── Example files ──");
for (const ex of examples) {
  check(`examples/${ex}`, `examples/${ex}`);
}

// Content checks on SKILL.md
console.log("\n── SKILL.md content ──");
checkContent("SKILL.md", [
  { pattern: /name:\s*zama-fhevm-skill/, description: "name: zama-fhevm-skill in frontmatter" },
  { pattern: /Non-Negotiable Defaults/, description: "Non-Negotiable Defaults section" },
  { pattern: /Default Workflow/, description: "Default Workflow section" },
  { pattern: /Required Correctness Checks/, description: "Required Correctness Checks section" },
  { pattern: /Version Guardrails/, description: "Version Guardrails section" },
  { pattern: /FHE\.makePubliclyDecryptable/, description: "FHE.makePubliclyDecryptable referenced" },
  { pattern: /ZamaEthereumConfig/, description: "ZamaEthereumConfig referenced" },
  { pattern: /relayer-sdk/, description: "@zama-fhe/relayer-sdk referenced" },
  { pattern: /2048/, description: "2048-bit decryption limit mentioned" },
  { pattern: /error-reference/, description: "error-reference linked" },
], "SKILL.md");

// Content checks on decryption.md
console.log("\n── decryption.md content ──");
checkContent("references/decryption.md", [
  { pattern: /makePubliclyDecryptable/, description: "FHE.makePubliclyDecryptable" },
  { pattern: /checkSignatures/, description: "FHE.checkSignatures" },
  { pattern: /EIP-712/, description: "EIP-712 user decryption" },
], "references/decryption.md");

// Content checks on error-reference.md
console.log("\n── error-reference.md content ──");
checkContent("references/error-reference.md", [
  { pattern: /ACL/, description: "ACL errors covered" },
  { pattern: /allowThis|allow\(/, description: "FHE.allow errors covered" },
  { pattern: /fromExternal|inputProof/, description: "input proof errors covered" },
], "references/error-reference.md");

// ─── Summary ─────────────────────────────────────────────────────────────────

console.log("\n" + "─".repeat(50));
console.log(`  Errors:   ${errors}`);
console.log(`  Warnings: ${warnings}`);

if (errors === 0 && warnings === 0) {
  console.log("\n  ✅  All checks passed — skill structure is valid.\n");
  process.exit(0);
} else if (errors === 0 && !strict) {
  console.log("\n  ⚠️   No errors, but warnings present. Run with --strict to fail on warnings.\n");
  process.exit(0);
} else {
  console.log("\n  ❌  Validation failed. Fix the issues above and re-run.\n");
  process.exit(1);
}
