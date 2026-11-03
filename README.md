# euromail-skills

Claude Code skills for [euromail.dev](https://euromail.dev) — GDPR-compliant transactional email API with EU data residency (Finland).

## Skills

### `/euromail`

Integrates euromail.dev into any project end-to-end:

1. Detects tech stack (Node.js, Python, Rust, Go, PHP, WordPress)
2. Installs the correct SDK, or the WordPress plugin
3. Resolves `EUROMAIL_API_KEY` from env, `.env`, or shell profiles
4. Detects or adds a verified sending domain
5. Sends a test email
6. Writes a reusable email service module

It also covers SMTP sending, the MCP server, signup forms and agent mailboxes, and points to the API reference served by euromail.dev.

Works with Claude Code and other agents that support the SKILL.md standard (Cursor, Windsurf, Codex CLI).

## Installation

### Claude Code (manual)

```bash
# Personal (all projects)
cp -r euromail ~/.claude/skills/

# Project-only
cp -r euromail /your/project/.claude/skills/
```

### skillshare

```bash
skillshare install github.com/kalle-works/euromail-skills
```

### One-liner (curl)

```bash
mkdir -p ~/.claude/skills && \
  curl -fsSL https://raw.githubusercontent.com/kalle-works/euromail-skills/main/install.sh | sh
```

## Usage

```
/euromail
```

The skill will guide you through the full setup. You need a euromail API key — get one at [dashboard.euromail.dev/api-keys](https://dashboard.euromail.dev/api-keys).

## Requirements

- Claude Code CLI, or any agent that supports SKILL.md
- A euromail account ([euromail.dev](https://euromail.dev))
- `EUROMAIL_API_KEY` (the skill will prompt you if not found)
