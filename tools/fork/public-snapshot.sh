#!/usr/bin/env bash
# Dena.emu GB: make a history-free commit of the current tree for the public
# repository (docs/dev/gb-fork.md, Public repository). Usage:
#   tools/fork/public-snapshot.sh <public-remote-url> <message>
# Commits on top of the public repository's main when it exists, so its own
# history is one commit per published snapshot.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
url=$1 msg=$2
tree=$(git rev-parse HEAD^{tree})
parent=()
if git fetch -q "$url" main 2>/dev/null; then
  parent=(-p FETCH_HEAD)
fi
commit=$(git commit-tree "$tree" "${parent[@]}" -m "$msg")
git push "$url" "$commit:refs/heads/main"
echo "pushed $commit"
