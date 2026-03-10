#!/bin/bash
# check-tasks.sh - Check Google Tasks for overdue/upcoming items
# Usage: check-tasks.sh [--account EMAIL] [--days-ahead N]

set -euo pipefail

ACCOUNT="${TASKS_ACCOUNT:-davidgarwin@gmail.com}"
DAYS_AHEAD=1  # Default: today and tomorrow only

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --account)
      ACCOUNT="$2"
      shift 2
      ;;
    --days-ahead)
      DAYS_AHEAD="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Get current date in ISO format (YYYY-MM-DD)
TODAY=$(date -u +%Y-%m-%d)
CUTOFF_DATE=$(date -u -d "+${DAYS_AHEAD} days" +%Y-%m-%d)

# Task lists to check
LISTS=("P0" "P1" "P2" "P3")

# Temp file for collecting tasks
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

echo "Checking tasks for account: $ACCOUNT" >&2
echo "Today: $TODAY | Cutoff: $CUTOFF_DATE" >&2
echo "" >&2

# First, fetch all task list IDs
echo "Fetching task list IDs..." >&2
declare -A LIST_IDS
while IFS=$'\t' read -r title id; do
  LIST_IDS["$title"]="$id"
done < <(gog tasks lists list --account "$ACCOUNT" --json 2>/dev/null | \
  jq -r '.tasklists[] | "\(.title)\t\(.id)"')

# Fetch tasks from each list
for LIST in "${LISTS[@]}"; do
  LIST_ID="${LIST_IDS[$LIST]}"
  
  if [[ -z "$LIST_ID" ]]; then
    echo "Warning: Task list '$LIST' not found" >&2
    continue
  fi
  
  echo "Fetching $LIST tasks (ID: $LIST_ID)..." >&2
  
  # Run gog tasks list and parse JSON output
  gog tasks list "$LIST_ID" --account "$ACCOUNT" --json 2>/dev/null | \
    jq -r --arg list "$LIST" --arg today "$TODAY" --arg cutoff "$CUTOFF_DATE" '
      .tasks[]? | 
      select(.due != null) |
      .dueDate = (.due | split("T")[0]) |
      select(.dueDate <= $cutoff) |
      "\($list)\t\(.title)\t\(.dueDate)\t\(.status // "needsAction")"
    ' >> "$TEMP_FILE" || true
done

# Check if we found any tasks
if [[ ! -s "$TEMP_FILE" ]]; then
  echo "NO_REPLY"
  exit 0
fi

# Sort by due date, then format output
{
  echo "**Overdue & Upcoming Tasks:**"
  echo ""
  
  # Group by priority
  for LIST in "${LISTS[@]}"; do
    TASKS=$(grep "^$LIST" "$TEMP_FILE" | sort -t$'\t' -k3 || true)
    
    if [[ -n "$TASKS" ]]; then
      # Determine if any are overdue
      OVERDUE=$(echo "$TASKS" | awk -F'\t' -v today="$TODAY" '$3 < today' || true)
      DUE_SOON=$(echo "$TASKS" | awk -F'\t' -v today="$TODAY" '$3 >= today' || true)
      
      if [[ -n "$OVERDUE" ]]; then
        echo "**$LIST (OVERDUE):**"
        echo "$OVERDUE" | while IFS=$'\t' read -r priority title due status; do
          echo "• $title — Due $due"
        done
        echo ""
      fi
      
      if [[ -n "$DUE_SOON" ]]; then
        if [[ -z "$OVERDUE" ]]; then
          echo "**$LIST:**"
        fi
        echo "$DUE_SOON" | while IFS=$'\t' read -r priority title due status; do
          # Calculate days until due
          DAYS_DIFF=$(( ($(date -d "$due" +%s) - $(date -d "$TODAY" +%s)) / 86400 ))
          
          if [[ $DAYS_DIFF -eq 0 ]]; then
            echo "• $title — Due today"
          elif [[ $DAYS_DIFF -eq 1 ]]; then
            echo "• $title — Due tomorrow ($due)"
          else
            echo "• $title — Due $due"
          fi
        done
        echo ""
      fi
    fi
  done
} | sed '/^$/N;/^\n$/D'  # Remove multiple blank lines

echo ""
