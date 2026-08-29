#!/usr/bin/env bash
# Cuts master into four review branches, each under the 300-file cap CodeRabbit reads,
# and pushes them.
#
# Bash rather than PowerShell, unlike the rest of `tool/`: this is entirely git plumbing,
# and `commit-tree`/`update-index --index-info` in PowerShell is a pipeline-encoding
# argument with no upside. Nothing here touches the Android toolchain, so the
# PROGRAMFILES warning in CLAUDE.md does not apply.
#
# The slices are boundaries somebody would review as a unit — the shared core, the
# security boundary, the two customer-facing apps, the admin — and `docs/`, `brand/` and
# CLAUDE.md ride in all four, because a reviewer reading a screen needs the decision
# behind it.
#
# **Every workspace member's pubspec.yaml rides in all four too, whether or not its code
# does.** That is the reason this file exists rather than four hand-run `commit-tree`s.
# A slice carrying the root `pubspec.yaml` — which lists `apps/admin_app` — and none of
# that directory is a workspace Dart cannot resolve, and the reviewer reports it as a
# defect. It is not one; it is the cut. Two findings were spent disproving exactly that,
# and each cost a round trip.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# What a reviewer needs to judge anything, plus the pubspecs that make the workspace
# resolve in isolation.
# `brand/src` and not `brand/` — the generated PNGs and SVGs are 40 files of output
# nobody reviews, and they crowd out code under the cap.
common='.gitattributes .gitignore CLAUDE.md THIRD_PARTY_NOTICES.md README.md
        analysis_options.yaml pubspec.yaml pubspec.lock
        apps/admin_app/pubspec.yaml apps/customer_app/pubspec.yaml
        apps/merchant_app/pubspec.yaml packages/luqma_core/pubspec.yaml
        brand/src brand/README.md docs tool'

slice() {
  local branch="$1"; shift
  local index; index="$(mktemp)"
  rm -f "$index"

  # A path list, then one `update-index --index-info` — the real index is never touched,
  # so this is safe to run with work in progress.
  local paths=()
  for p in $common "$@"; do [ -e "$p" ] && paths+=("$p"); done

  local count
  count="$(GIT_INDEX_FILE="$index" git ls-tree -r HEAD -- "${paths[@]}" | wc -l)"
  if [ "$count" -gt 300 ]; then
    # Louder than a truncated review: over the cap the reviewer drops files silently, and
    # a slice that was quietly not read looks exactly like one that came back clean.
    echo "$branch has $count files, over the 300 the reviewer reads. Split it." >&2
    rm -f "$index"; return 1
  fi

  GIT_INDEX_FILE="$index" git ls-tree -r HEAD -- "${paths[@]}" \
    | GIT_INDEX_FILE="$index" git update-index --index-info
  local tree commit parent
  tree="$(GIT_INDEX_FILE="$index" git write-tree)"

  # Each refresh is a *child* of the previous slice tip, never a fresh orphan.
  #
  # It looks like a view of master and it is, but a reviewer's inline comments are
  # anchored to the commit they were written against. Replacing the branch with an
  # unrelated orphan makes those commits unreachable, and every reply is then refused
  # with "commit_id is not part of the pull request" — the whole review becomes
  # unanswerable in place. That cost a round of replies once; the parent is the fix.
  parent="$(git rev-parse --verify --quiet "refs/heads/$branch" || true)"
  if [ -n "$parent" ]; then
    commit="$(git commit-tree "$tree" -p "$parent"       -m "Refresh $branch to $(git rev-parse --short HEAD)")"
  else
    commit="$(git commit-tree "$tree" -m "$branch at $(git rev-parse --short HEAD)")"
  fi
  git branch -f "$branch" "$commit"
  rm -f "$index"
  printf '%-18s %s files\n' "$branch" "$count"
}

slice review-core     packages/luqma_core
slice review-boundary supabase data packages/luqma_core/lib/src/repositories
# The apps carry `luqma_core/lib` and not its tests. A reviewer reading a screen needs
# the API the screen calls; the core's own suite is `review-core`'s subject, and
# including it here is what puts this slice over the cap.
slice review-apps     apps/customer_app apps/merchant_app packages/luqma_core/lib
slice review-admin    apps/admin_app packages/luqma_core/lib

if [ "${1:-}" = "--push" ]; then
  git push --force-with-lease origin \
    review-core review-boundary review-apps review-admin
fi
