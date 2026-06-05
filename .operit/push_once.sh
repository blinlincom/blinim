#!/usr/bin/env bash
# One-shot GitHub Git Data API pusher for this workspace.
# Usage:
#   TOKEN=ghp_xxx ./.operit/push_once.sh "commit message" file1 file2 ...
# It creates one commit no matter how many files are passed.
set -u

REPO="${REPO:-blinlincom/imblinlin}"
BRANCH="${BRANCH:-main}"
TOKEN="${TOKEN:-}"
MSG="${1:-}"
shift || true

if [ -z "$TOKEN" ]; then echo "TOKEN is required" >&2; exit 1; fi
if [ -z "$MSG" ]; then echo "commit message is required" >&2; exit 1; fi
if [ "$#" -eq 0 ]; then echo "at least one file is required" >&2; exit 1; fi

API="https://api.github.com/repos/$REPO"
H1="Authorization: Bearer $TOKEN"
H2="Accept: application/vnd.github+json"
H3="X-GitHub-Api-Version: 2022-11-28"

REF=$(curl -sS -H "$H1" -H "$H2" -H "$H3" "$API/git/ref/heads/$BRANCH")
BASE_SHA=$(echo "$REF" | sed -n 's/.*"sha": *"\([0-9a-f]*\)".*/\1/p' | head -1)
if [ -z "$BASE_SHA" ]; then echo "failed to get base sha: $REF" >&2; exit 2; fi

COMMIT=$(curl -sS -H "$H1" -H "$H2" -H "$H3" "$API/git/commits/$BASE_SHA")
BASE_TREE=$(echo "$COMMIT" | sed -n 's/.*"sha": *"\([0-9a-f]*\)".*/\1/p' | sed -n '2p')
if [ -z "$BASE_TREE" ]; then echo "failed to get base tree: $COMMIT" >&2; exit 3; fi

echo "base=$BASE_SHA tree=$BASE_TREE"
TREE_ITEMS=""
for P in "$@"; do
  if [ ! -f "$P" ]; then echo "missing file: $P" >&2; exit 4; fi
  B64=$(base64 "$P" | tr -d '\n')
  BODY='{"content":"'$B64'","encoding":"base64"}'
  RESP=$(curl -sS -H "$H1" -H "$H2" -H "$H3" -X POST "$API/git/blobs" -d "$BODY")
  SHA=$(echo "$RESP" | sed -n 's/.*"sha": *"\([0-9a-f]*\)".*/\1/p' | head -1)
  if [ -z "$SHA" ]; then echo "blob failed for $P: $RESP" >&2; exit 5; fi
  echo "blob $P $SHA"
  ITEM='{"path":"'$P'","mode":"100644","type":"blob","sha":"'$SHA'"}'
  if [ -z "$TREE_ITEMS" ]; then TREE_ITEMS="$ITEM"; else TREE_ITEMS="$TREE_ITEMS,$ITEM"; fi
done

TREE_BODY='{"base_tree":"'$BASE_TREE'","tree":['$TREE_ITEMS']}'
TREE_RESP=$(curl -sS -H "$H1" -H "$H2" -H "$H3" -X POST "$API/git/trees" -d "$TREE_BODY")
NEW_TREE=$(echo "$TREE_RESP" | sed -n 's/.*"sha": *"\([0-9a-f]*\)".*/\1/p' | head -1)
if [ -z "$NEW_TREE" ]; then echo "tree failed: $TREE_RESP" >&2; exit 6; fi

ESC_MSG=$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g')
COMMIT_BODY='{"message":"'$ESC_MSG'","tree":"'$NEW_TREE'","parents":["'$BASE_SHA'"]}'
COMMIT_RESP=$(curl -sS -H "$H1" -H "$H2" -H "$H3" -X POST "$API/git/commits" -d "$COMMIT_BODY")
NEW_COMMIT=$(echo "$COMMIT_RESP" | sed -n 's/.*"sha": *"\([0-9a-f]*\)".*/\1/p' | head -1)
if [ -z "$NEW_COMMIT" ]; then echo "commit failed: $COMMIT_RESP" >&2; exit 7; fi

PATCH_BODY='{"sha":"'$NEW_COMMIT'","force":false}'
PATCH_RESP=$(curl -sS -H "$H1" -H "$H2" -H "$H3" -X PATCH "$API/git/refs/heads/$BRANCH" -d "$PATCH_BODY")
UPDATED=$(echo "$PATCH_RESP" | sed -n 's/.*"sha": *"\([0-9a-f]*\)".*/\1/p' | head -1)
if [ "$UPDATED" != "$NEW_COMMIT" ]; then echo "ref update maybe failed: $PATCH_RESP" >&2; exit 8; fi

echo "pushed $NEW_COMMIT"
