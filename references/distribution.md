# Distribution and Installation Guide

How to install and use the `zama-fhevm-skill` package across different AI coding tools.

---

## Package Layout

```
zama-fhevm-skill/
├── SKILL.md                          ← Main routing layer (all tools)
├── AGENTS.md                         ← Codex / plain-markdown adapter
├── README.md                         ← Human-readable overview
├── agents/
│   └── openai.yaml                   ← Codex app metadata
├── .cursor/
│   └── rules/
│       └── zama-fhevm.mdc            ← Cursor rule adapter
├── scripts/
│   └── validate-skill.mjs            ← Structural validator (Node.js)
├── references/                       ← 17 focused technical references
│   ├── architecture.md
│   ├── setup.md
│   ├── solidity-patterns.md
│   ├── encrypted-types.md
│   ├── fhe-operations.md
│   ├── access-control.md
│   ├── input-proofs.md
│   ├── decryption.md
│   ├── frontend-integration.md
│   ├── testing.md
│   ├── deployment.md
│   ├── oz-confidential.md
│   ├── error-reference.md            ← 50+ errors with root cause + fix
│   ├── anti-patterns.md              ← 15 common mistakes
│   ├── addresses.md
│   ├── validation.md
│   └── distribution.md
└── examples/                         ← 7 production-ready code examples
    ├── hardhat.config.ts
    ├── ConfidentialCounter.sol
    ├── ConfidentialToken.sol
    ├── ConfidentialVoting.sol
    ├── ConfidentialAuction.sol
    ├── frontend-integration.tsx
    └── test-example.ts
```

---

## Installation Paths

### Claude Code

Drop `SKILL.md` into your project and reference it in your system prompt or `CLAUDE.md`:

```bash
# Copy into project
cp -r zama-fhevm-skill/ /your/project/.skills/zama-fhevm-skill/

# Reference in CLAUDE.md
echo "Use the FHEVM skill at .skills/zama-fhevm-skill/SKILL.md for all confidential contract work." >> CLAUDE.md
```

Or load it directly:
```
/load .skills/zama-fhevm-skill/SKILL.md
```

### GitHub Copilot (Agent Skills)

```bash
# Project-scoped
cp -r zama-fhevm-skill/ .github/skills/zama-fhevm-skill/

# User-scoped
cp -r zama-fhevm-skill/ ~/.copilot/skills/zama-fhevm-skill/
```

Keep the directory name matching the `name` field in `SKILL.md`.

### Codex / OpenAI Codex

```bash
# Install as Codex skill
cp -r zama-fhevm-skill/ .agents/skills/zama-fhevm-skill/

# Or copy plain-markdown adapter to project root
cp zama-fhevm-skill/AGENTS.md ./AGENTS.md
```

### Cursor

**Option A — Project rule** (recommended):
```bash
mkdir -p .cursor/rules
cp zama-fhevm-skill/.cursor/rules/zama-fhevm.mdc .cursor/rules/
```

**Option B — Remote import** (Cursor supports MDC remote imports):
Reference the `.mdc` file from your GitHub repository URL in Cursor's rule settings.

**Option C — Plain markdown**:
```bash
cp zama-fhevm-skill/AGENTS.md ./AGENTS.md
```

### Windsurf

Place `SKILL.md` in `.windsurf/skills/` or add it to your global rules:

```bash
mkdir -p .windsurf/skills
cp -r zama-fhevm-skill/ .windsurf/skills/
```

### skills.sh / GitHub Distribution

To publish through a GitHub repository, make the `zama-fhevm-skill/` directory the repository root, or place it as one skill folder in a multi-skill repository. Consumers install with:

```bash
npx skills add <your-github-username>/zama-fhevm-skill
```

---

## Adapter Matrix

| Adapter | Best for | What it contains |
|---|---|---|
| `SKILL.md` | Claude Code, Copilot, Agent Skills | Full routing layer, activation cues, non-negotiable defaults, reference map |
| `AGENTS.md` | Codex, plain-markdown environments | Short project instructions pointing to SKILL.md and key references |
| `.cursor/rules/zama-fhevm.mdc` | Cursor (project or global rule) | Lightweight activation triggers, inline code patterns, reference pointers |
| `agents/openai.yaml` | Codex app metadata | Structured metadata for Codex-oriented distribution |

---

## Validation

After installation or after editing skill files, run the structural validator:

```bash
node scripts/validate-skill.mjs
```

This checks that all files referenced in `SKILL.md` exist and that required sections are present.

---

## Keeping the Skill Up to Date

The Zama Protocol updates frequently. When you detect any of the following in generated code, the skill may need a refresh:

- Agent uses `TFHE` namespace (deprecated)
- Agent uses `einput` parameter type (deprecated)
- Agent references `fhevmjs` as the primary frontend SDK (deprecated in favor of `@zama-fhe/relayer-sdk`)
- Agent hardcodes Zama infrastructure addresses
- Agent uses old `gateway.requestDecryption()` API without `FHE.makePubliclyDecryptable`

Check the [Zama Protocol docs](https://docs.zama.org/protocol) and update:
1. `references/addresses.md` for new contract addresses
2. `references/setup.md` for dependency version changes
3. `SKILL.md` metadata `protocol_baseline` date

---

## Directory Name Convention

The Agent Skills spec requires the installation directory name to match the `name` field in `SKILL.md`. The canonical name is `zama-fhevm-skill`. Do not rename the directory when installing.
