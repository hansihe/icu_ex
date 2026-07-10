# How to release

Because we use
[`RustlerPrecompiled`](https://hexdocs.pm/rustler_precompiled/RustlerPrecompiled.html),
releasing involves building NIFs on CI and checksumming the resulting
artifacts. Most of the process is automated by
[`scripts/release.sh`](scripts/release.sh).

## Prerequisites

* `gh` CLI, authenticated (`gh auth status`).
* hex.pm authentication (`mix hex.user whoami`).
* A clean working tree checked out at the latest `main`.

## Steps

1. Run `scripts/release.sh prepare [version]`.

    * `version` defaults to the version in `mix.exs` with `-dev` removed.
      We follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
    * This creates a draft GitHub release with generated notes, seeds
      `CHANGELOG.md` from them, bumps the version in `mix.exs` and
      `README.md`, and opens a release PR.
    * The script pauses after seeding `CHANGELOG.md` — edit the raw notes
      into [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) form
      before continuing.

2. Review and merge the release PR.

3. Update your local `main` (`jj git fetch && jj new main`), then run
   `scripts/release.sh publish <version>`.

    * This publishes the GitHub release, which creates the tag and kicks off
      the "Precomp NIFs" workflow. The script waits for it to complete
      (usually 40–60 minutes), so feel free to walk away.
    * It then downloads the artifacts, generates the checksums, and appends
      them to the release notes.
    * Finally it runs `mix hex.publish --yes` and pushes a commit to `main`
      bumping `mix.exs` to the next patch version with a `-dev` suffix
      (e.g. `0.11.0` → `0.11.1-dev`).

Both commands are resumable: if something fails partway, fix the issue and
rerun the same command — completed steps are detected and skipped.

## Manual fallback

If the script is unusable for some reason, it is a faithful encoding of the
manual process; follow its steps by hand in order. The pre-automation
version of this document (with full manual instructions) is available in
git history.
