#!/usr/bin/env bash
#
# Release automation for icu_ex. See RELEASE.md for an overview of the process.
#
# Usage:
#   scripts/release.sh prepare [version]
#       Create a draft GitHub release, seed CHANGELOG.md from the generated
#       notes (pauses for you to edit), bump versions, and open a release PR.
#
#   scripts/release.sh publish [version]
#       After the release PR is merged: publish the GitHub release (creates
#       the tag, which kicks off the NIF builds), wait for the builds,
#       generate and attach artifact checksums, publish to hex.pm, and bump
#       main to the next -dev version.
#
# Both commands are resumable: rerun after a failure and already-completed
# steps are skipped.

set -euo pipefail

REPO="hansihe/icu_ex"
NIF_MODULE="Icu.Nif"
CHECKSUM_FILE="checksum-Elixir.Icu.Nif.exs"
NIF_WORKFLOW="release.yml"

cd "$(dirname "$0")/.."

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

mix_version() {
  perl -ne 'print $1 if /^\s*\@version "([^"]+)"/' mix.exs
}

set_mix_version() {
  NEW_VERSION="$1" perl -pi -e \
    's/\@version "[^"]+"/\@version "$ENV{NEW_VERSION}"/' mix.exs
}

# Field of the (draft or published) release for a tag, "null" if none exists.
# Drafts have no real tag yet, so we go through the release list endpoint.
# Note: no `// empty` here — jq's alternative operator would swallow a
# legitimate `false` for the draft field.
release_field() {
  gh api "repos/$REPO/releases" \
    --jq "[.[] | select(.tag_name == \"$1\")][0].$2"
}

require_tools() {
  command -v gh >/dev/null || die "gh CLI is required"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated (gh auth login)"
}

require_clean_tree_at_main() {
  [ -z "$(git status --porcelain)" ] || die "working tree is not clean"
  git fetch origin main
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] ||
    die "not at latest origin/main — update first (jj: 'jj git fetch && jj new main')"
}

prepare() {
  local version="${1:-}"
  if [ -z "$version" ]; then
    version="$(mix_version)"
    version="${version%-dev}"
  fi
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid version: $version"
  local tag="v$version"

  require_tools
  require_clean_tree_at_main

  [ -z "$(git ls-remote --tags origin "refs/tags/$tag")" ] ||
    die "tag $tag already exists — pass the new version explicitly"
  ! git rev-parse --verify -q "release-$tag" >/dev/null ||
    die "branch release-$tag already exists — delete it first (git branch -D release-$tag)"

  local notes
  notes="$(release_field "$tag" body)"
  if [ -z "$notes" ] || [ "$notes" = "null" ]; then
    info "Creating draft release $tag with generated notes"
    gh release create "$tag" --target main --generate-notes --draft
    notes="$(release_field "$tag" body)"
  else
    info "Draft release $tag already exists, reusing its notes"
  fi

  git switch -c "release-$tag" origin/main

  if grep -q "^## \[$version\]" CHANGELOG.md; then
    info "CHANGELOG.md already has a section for $version"
  else
    info "Seeding CHANGELOG.md with the generated release notes"
    local notes_file
    notes_file="$(mktemp)"
    printf '%s\n' "$notes" >"$notes_file"
    awk -v ver="$version" -v date="$(date +%Y-%m-%d)" -v nf="$notes_file" '
      { print }
      /^## \[Unreleased\]$/ {
        print ""
        print "## [" ver "] - " date
        print ""
        while ((getline line < nf) > 0) print line
      }
    ' CHANGELOG.md >CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
    rm -f "$notes_file"
    echo
    echo "The raw generated notes were inserted under '## [$version]' in CHANGELOG.md."
    echo "Edit them into Keep a Changelog form (https://keepachangelog.com/en/1.1.0/)."
    read -rp "Press Enter when CHANGELOG.md is ready... "
  fi

  info "Bumping version to $version in mix.exs and README.md"
  set_mix_version "$version"
  NEW_VERSION="$version" perl -pi -e \
    's/\{:icu, "~> [^"]+"\}/{:icu, "~> $ENV{NEW_VERSION}"}/g' README.md

  git add mix.exs README.md CHANGELOG.md
  git commit -m "Release $tag"
  git push -u origin "release-$tag"
  gh pr create --title "Release $tag" --body "Prepares the $tag release.

- Bump version to $version
- Update CHANGELOG.md"

  echo
  info "Next: review and merge the PR, update your local main, then run:"
  info "  scripts/release.sh publish $version"
}

publish() {
  local version="${1:-$(mix_version)}"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid version: $version"
  local tag="v$version"

  require_tools
  require_clean_tree_at_main
  [ "$(mix_version)" = "$version" ] ||
    die "mix.exs has $(mix_version), expected $version — is the release PR merged and your checkout updated?"

  case "$(release_field "$tag" draft)" in
    true)
      info "Publishing release $tag (this creates the tag and starts the NIF builds)"
      gh release edit "$tag" --draft=false
      ;;
    false) info "Release $tag is already published, continuing" ;;
    *) die "no release found for $tag — run 'scripts/release.sh prepare' first" ;;
  esac

  info "Looking for the '$NIF_WORKFLOW' run for $tag..."
  local run_id=""
  for _ in $(seq 1 60); do
    run_id="$(gh run list --workflow "$NIF_WORKFLOW" --branch "$tag" --limit 1 \
      --json databaseId --jq '.[0].databaseId // empty')"
    [ -n "$run_id" ] && break
    sleep 10
  done
  [ -n "$run_id" ] || die "no NIF build run appeared for $tag"

  info "Waiting for NIF builds (run $run_id, usually 40-60 minutes)..."
  gh run watch "$run_id" --exit-status

  info "Downloading artifacts and generating checksums"
  rm -rf target
  rm -f "$CHECKSUM_FILE"
  local dl_log checksums
  dl_log="$(mktemp)"
  ICU_BUILD=true mix rustler_precompiled.download "$NIF_MODULE" --all --print | tee "$dl_log"
  checksums="$(grep -E '^[0-9a-f]{64}  ' "$dl_log" || true)"
  rm -f "$dl_log"
  [ -n "$checksums" ] || die "no checksums found in download output"

  local body
  body="$(gh release view "$tag" --json body -q .body)"
  if grep -q "SHA256 of the artifacts" <<<"$body"; then
    info "Release notes already contain checksums"
  else
    info "Appending checksums to the release notes"
    local notes_file
    notes_file="$(mktemp)"
    printf '%s\n\n## SHA256 of the artifacts\n```\n%s\n```\n' "$body" "$checksums" >"$notes_file"
    gh release edit "$tag" --notes-file "$notes_file"
    rm -f "$notes_file"
  fi

  info "Publishing to hex.pm"
  mix hex.publish --yes
  rm -f "$CHECKSUM_FILE"

  local next
  IFS=. read -r major minor patch <<<"$version"
  next="$major.$minor.$((patch + 1))-dev"
  info "Bumping main to $next"
  set_mix_version "$next"
  git add mix.exs
  git commit -m "Bump version to $next"
  git push origin HEAD:refs/heads/main

  echo
  info "Release $tag is done!"
  info "If you use jj, sync up with: jj git fetch && jj new main"
}

case "${1:-}" in
  prepare) prepare "${2:-}" ;;
  publish) publish "${2:-}" ;;
  *)
    echo "usage: scripts/release.sh {prepare|publish} [version]" >&2
    exit 2
    ;;
esac
