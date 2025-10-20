# Repository Guidelines

## Project Structure & Module Organization
Icu delivers idiomatic Elixir wrappers around ICU4X via Rustler NIFs. Elixir sources live under `lib/icu`, grouped by formatter type (`date_formatter`, `number_formatter`, etc.) with `lib/icu.ex` exposing the public API. NIF bindings reside in `native/icu_nif/src`, mirroring the Elixir modules with Rust implementations and specs alongside. Test suites are in `test/icu`. The `cldr/` directory bundles upstream CLDR reference assets; treat it as read-only context rather than runtime data. Generated artifacts land in `_build/` and `priv/`; avoid committing them unless explicitly versioned.

## Build, Test, and Development Commands
- `mix deps.get` — install or update Elixir dependencies before first build.
- `mix compile` — compile Elixir modules and rebuild the NIF if sources changed.
- `mix test` — run the ExUnit suite; add `mix test path/to/file_test.exs:line` for focused runs.
- `mix format` — format the Elixir codebase; run before committing.
- `cargo test --manifest-path native/icu_nif/Cargo.toml` — execute Rust-side unit tests for the NIF.
- `cargo fmt --manifest-path native/icu_nif/Cargo.toml` — apply Rust formatting to keep bindings consistent.

## Coding Style & Naming Conventions
Follow idiomatic Elixir: two-space indentation, module names in PascalCase (`Icu.DateFormatter`), functions and variables in `snake_case`. Keep public functions documented with `@doc` blocks when behavior is non-trivial. Enforce formatting with `mix format`; never hand-edit generated formatter layouts. For Rust, rely on `cargo fmt`, prefer `?` over `unwrap`, and map errors to `rustler::Error` with clear context strings.

## Testing Guidelines
Use ExUnit and place tests under `test/icu`, matching the source file name (`date_formatter_test.exs`). Include both happy-path assertions and locale edge cases using fixtures from `cldr/`. When touching Rust code, update or add Rust unit tests and re-run `mix test` to ensure the beam integration still works. Aim to keep new modules covered by at least one integration test that exercises the corresponding NIF call.

## Commit & Pull Request Guidelines
Write imperative, present-tense commit subjects (`Add zoned time formatter`) and include a short body when explaining rationale or side effects. Group related Elixir and Rust changes within the same commit to preserve cross-language coherence. Pull requests should describe the change, list validation steps (`mix test`, `cargo test`), and reference any relevant issue IDs. Add screenshots or sample outputs when modifying formatter behavior so reviewers can verify locale-sensitive changes quickly.

## Native Integration Tips
When altering NIF signatures, update both the Rust `lib.rs` exports and the matching functions in `lib/icu/*.ex`. Regenerate the shared library via `mix compile`, and confirm the compiled artifact appears in `priv/`. Keep ICU4X crate versions aligned across `mix.exs` (Rustler) and `native/icu_nif/Cargo.toml`; document noteworthy upgrades in PR descriptions so Elixir consumers understand behavior shifts.
