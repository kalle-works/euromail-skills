#!/bin/sh
# Install euromail skills for Claude Code
# Usage: curl -fsSL https://raw.githubusercontent.com/kalle-works/euromail-skills/main/install.sh | sh

set -e

REPO="https://raw.githubusercontent.com/kalle-works/euromail-skills/main"
SKILLS_DIR="${HOME}/.claude/skills"

mkdir -p "${SKILLS_DIR}/euromail"

echo "Installing euromail skill..."
curl -fsSL "${REPO}/euromail/SKILL.md" -o "${SKILLS_DIR}/euromail/SKILL.md"
echo "Done. Run /euromail in Claude Code to integrate euromail.dev into your project."
