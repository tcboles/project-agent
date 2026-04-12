#!/bin/bash
# Track agent progress by logging tool usage to data/activity.log
# Fires on Edit/Write operations to give visibility into what agents are doing.
#
# Input: JSON on stdin with tool_name, tool_input fields
# Output: JSON on stdout (passthrough — we don't block anything)

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
LOG_FILE="${PLUGIN_ROOT}/data/activity.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Read the hook input
INPUT=$(cat)

# Extract tool name and file path from the input
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); i=d.get('tool_input',{}); print(i.get('file_path', i.get('command',''))[:120])" 2>/dev/null || echo "unknown")

# Append to activity log (create data dir if needed)
mkdir -p "$(dirname "$LOG_FILE")"
echo "${TIMESTAMP} | ${TOOL_NAME} | ${FILE_PATH}" >> "$LOG_FILE"

# Pass through — don't block anything
echo '{"decision": "approve"}'
