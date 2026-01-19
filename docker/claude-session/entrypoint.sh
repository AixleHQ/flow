#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  PALAD Session: ${YELLOW}${STEP_NAME:-unknown}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Clone repo if URL provided
if [ -n "$REPO_URL" ]; then
    echo -e "${GREEN}📦 Cloning repository...${NC}"
    git clone --depth 1 "$REPO_URL" /workspace/repo 2>/dev/null || {
        echo -e "${YELLOW}⚠️  Failed to clone repo: $REPO_URL${NC}"
    }
fi

# Create output directory
mkdir -p /workspace/output

# Setup Claude Code config directory
mkdir -p /workspace/.claude

# Create settings.json with permissions
cat > /workspace/.claude/settings.json << EOF
{
  "model": "${MODEL:-claude-sonnet-4-20250514}",
  "permissions": {
    "allow": [
      "Read",
      "Glob",
      "Grep",
      "Bash(git:*)",
      "Bash(cat:*)",
      "Bash(ls:*)",
      "Bash(find:*)",
      "Bash(head:*)",
      "Bash(tail:*)",
      "Bash(wc:*)",
      "Bash(tree:*)",
      "Bash(rg:*)",
      "Bash(fd:*)",
      "Edit(/workspace/output/**)",
      "Write(/workspace/output/**)"
    ],
    "deny": [
      "Bash(rm -rf:*)",
      "Bash(mv:*)",
      "Edit(/workspace/repo/**)",
      "Write(/workspace/repo/**)",
      "Edit(/workspace/context/**)",
      "Write(/workspace/context/**)"
    ],
    "defaultMode": "acceptEdits"
  }
}
EOF

# Copy step-specific CLAUDE.md prompt
if [ -n "$STEP_NAME" ] && [ -f "/prompts/${STEP_NAME}.md" ]; then
    cp "/prompts/${STEP_NAME}.md" /workspace/CLAUDE.md
    echo -e "${GREEN}✅ Loaded BMAD prompt for: ${STEP_NAME}${NC}"
else
    echo -e "${YELLOW}ℹ️  No specific prompt for step: ${STEP_NAME:-none}${NC}"
fi

# Show workspace info
echo ""
echo -e "  ${BLUE}Workspace:${NC}"
echo "    repo:    /workspace/repo"
echo "    context: /workspace/context"
echo "    output:  /workspace/output"
echo ""
echo -e "  ${BLUE}Commands:${NC}"
echo "    claude   - Start AI assistant"
echo "    exit     - Finish this step"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Start interactive shell
exec bash
