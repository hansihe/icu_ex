# Icu

`icu` exposes a variety of data and algorithms which are implemented in the `icu4x` Rust library to Elixir through a NIF.

## Installation

The package can be installed by adding `icu` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:icu, "~> 0.5.0"}
  ]
end
```

Documentation can be found at <https://hexdocs.pm/icu>.

## Number formatting

`Icu.Number.format/2` formats a number for a locale (defaulting to the `:icu`
`:default_locale`):

```elixir
Icu.Number.format(1_234.5, locale: "en")
#=> {:ok, "1,234.5"}
```

### Compact notation

`notation: :compact` renders locale-aware abbreviations. The powers used are
locale-dependent — English abbreviates thousands (`K`), Japanese and Chinese
group by 万 (10⁴) and do not abbreviate mere thousands:

```elixir
Icu.Number.format(194_438, locale: "en", notation: :compact)
#=> {:ok, "194K"}

Icu.Number.format(194_438, locale: "ja", notation: :compact)
#=> {:ok, "19万"}
```

- `:compact_display` — `:short` (default, `"194K"`) or `:long` (`"194 thousand"`).
- `:rounding_mode` — `:half_even` (default, matching ICU4X) or `:trunc`. With
  `:trunc` the abbreviation never overstates the value: `6_718` shows as `"6K"`,
  never `"7K"`.

`format_compact/2` additionally returns the exact integer the abbreviation
stands for, so callers can tell when the display understates the value (for
example, to append a localised "+"):

```elixir
Icu.Number.format_compact(6_718, locale: "en", rounding_mode: :trunc)
#=> {:ok, %{formatted: "6K", displayed_value: 6_000}}
```

`format_compact/2` is integer-domain (its `:displayed_value` is an integer): it
accepts integers and integer-valued floats/decimals and returns
`{:error, :invalid_number}` for a value with a fractional part. Use `format/2`
with `notation: :compact` to compact-format an arbitrary number for display only.

### Percent

`style: :percent` follows `Intl.NumberFormat` semantics — the input is a
**ratio**, multiplied by 100 — with locale-correct placement:

```elixir
Icu.Number.format(0.5, locale: "en", style: :percent)
#=> {:ok, "50%"}

Icu.Number.format(0.5, locale: "tr", style: :percent)
#=> {:ok, "%50"}
```

Percent shows no fraction digits unless `:maximum_fraction_digits` is set, and
cannot be combined with `notation: :compact`.

> Compact and percent both ride ICU4X's `experimental` feature
> (`CompactDecimalFormatter` / `PercentFormatter`), so their API and output may
> change with the pinned `icu4x` revision.
