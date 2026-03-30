#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

shell_fn="$(nix eval --raw --impure --expr "
  let
    lib = import <nixpkgs/lib>;
    paths = import ${REPO_ROOT}/nix/stackpanel/lib/paths.nix { inherit lib; };
  in
    paths.mkShellFindRoot {
      rootDir = \".stack\";
      rootMarker = \".stackpanel-root\";
    }
")"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

repo="$tmpdir/repo"
mkdir -p "$repo/.stack"
cd "$repo"

git init -q
printf '{}\n' > flake.nix
printf '%s\n' "$repo" > .stackpanel-root

git add flake.nix .stack .stackpanel-root
git -c user.name=test -c user.email=test@example.com commit -qm init

git worktree add -q .worktrees/feature -b feature
worktree="$repo/.worktrees/feature"
expected_root="$(cd "$worktree" && pwd -P)"

cd "$worktree"
source /dev/stdin <<< "$shell_fn"

actual_root="$(cd "$(stackpanel_find_root)" && pwd -P)"
if [[ "$actual_root" != "$expected_root" ]]; then
  echo "expected worktree root: $expected_root" >&2
  echo "actual root: $actual_root" >&2
  exit 1
fi

echo "worktree root resolved correctly"
