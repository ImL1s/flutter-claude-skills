#!/bin/bash
# App Store 評論檢查腳本 (使用 RSS feed)
# 
# Usage: ./app_review_watch.sh

set -euo pipefail

# Precise Apple IDs for active apps
declare -a APPS=(
  # Format: "APPLE_APP_ID|Human-Readable Name"
  # Replace with your own team's apps:
  # "1234567890|MyApp"
)

TOTAL_NEW=0
OUTPUT=""

# Fetch reviews for US and TW stores
for entry in "${APPS[@]}"; do
  IFS="|" read -r aid name <<< "$entry"
  
  # Fetch US reviews
  us_reviews=$(curl -s "https://itunes.apple.com/us/rss/customerreviews/id=${aid}/sortby=mostrecent/json" | \
    jq -r '.feed.entry[]? | select(."im:rating") | "⭐" + (."im:rating".label) + " | " + .title.label + " | " + (.content.label | .[0:150])' 2>/dev/null | head -5)
    
  if [ -n "$us_reviews" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      OUTPUT+="• $name $line\n"
      TOTAL_NEW=$((TOTAL_NEW+1))
    done <<< "$us_reviews"
  fi
  
  # Fetch TW reviews
  tw_reviews=$(curl -s "https://itunes.apple.com/tw/rss/customerreviews/id=${aid}/sortby=mostrecent/json" | \
    jq -r '.feed.entry[]? | select(."im:rating") | "⭐" + (."im:rating".label) + " [TW] | " + .title.label + " | " + (.content.label | .[0:150])' 2>/dev/null | head -3)
    
  if [ -n "$tw_reviews" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      OUTPUT+="• $name $line\n"
      TOTAL_NEW=$((TOTAL_NEW+1))
    done <<< "$tw_reviews"
  fi
  
  sleep 0.5
done

if [ "$TOTAL_NEW" -eq 0 ]; then
  echo "HEARTBEAT_OK"
  exit 0
fi

# Format output based on Agent rules
echo "📱 **App 評論檢查 — $(date +%Y-%m-%d)**"
echo ""

# Filter negative reviews
NEGATIVES=$(echo -e "$OUTPUT" | grep '⭐[12]') || true
if [ -n "$NEGATIVES" ]; then
  echo "**⚠️ 需關注**"
  echo "$NEGATIVES"
  echo ""
fi

# Filter positive reviews
POSITIVES=$(echo -e "$OUTPUT" | grep '⭐[45]') || true
if [ -n "$POSITIVES" ]; then
  echo "**✅ 正面評論**"
  echo "$POSITIVES"
  echo ""
fi

# Filter neutral reviews
NEUTRALS=$(echo -e "$OUTPUT" | grep '⭐3') || true
if [ -n "$NEUTRALS" ]; then
  echo "**💬 中性評論**"
  echo "$NEUTRALS"
  echo ""
fi

echo "📊 統計：檢查 ${#APPS[@]} 個 iOS App，共 $TOTAL_NEW 則新評論"
