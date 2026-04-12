#!/bin/bash
# Track agent progress by logging tool usage to .project-agent/activity.log
# in the current working directory (the project being managed).
#
# Input: JSON on stdin with tool_name, tool_input fields
# Output: JSON on stdout (passthrough — we don't block anything)

set -euo pipefail

LOG_FILE="${PWD}/.project-agent/activity.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Read the hook input
INPUT=$(cat)

# Extract tool name and file path from the input
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); i=d.get('tool_input',{}); print(i.get('file_path', i.get('command',''))[:120])" 2>/dev/null || echo "unknown")

# Only log if .project-agent/ exists in cwd (don't create it in random directories)
if [ -d "${PWD}/.project-agent" ]; then
  echo "${TIMESTAMP} | ${TOOL_NAME} | ${FILE_PATH}" >> "$LOG_FILE"
fi

# Pass through — don't block anything
echo '{"decision": "approve"}'
