use std::convert::TryFrom;
use std::fmt;

use fixed_decimal::Decimal as FixedDecimal;
use fixed_decimal::{CompactDecimal, FloatPrecision, SignDisplay};
use icu::decimal::options::{DecimalFormatterOptions, GroupingStrategy};
use icu::decimal::{parts, DecimalFormatter};
use icu::experimental::compactdecimal::{CompactDecimalFormatter, CompactDecimalFormatterOptions};
use icu::experimental::dimension::percent::formatter::PercentFormatter;
use rustler::types::map::MapIterator;
use rustler::types::BigInt;
use rustler::{Atom, Encoder, Env, NifMap, NifResult, ResourceArc, Term, TermType};
use writeable::{Part as WriteablePart, PartsWrite, Writeable};

use crate::atoms;
use crate::locale::LocaleResource;

pub(crate) struct NumberFormatterResource {
    formatter: FormatterKind,
    config: FormatterConfig,
}

impl rustler::Resource for NumberFormatterResource {}

/// The ICU4X formatter selected for this resource. Each style/notation maps to a
/// distinct ICU4X type, so the choice is made once at construction time.
enum FormatterKind {
    Standard(DecimalFormatter),
    // Boxed: these formatters are substantially larger than DecimalFormatter.
    Compact(Box<CompactDecimalFormatter>),
    Percent(Box<PercentFormatter<DecimalFormatter>>),
}

#[derive(Clone, Copy, PartialEq)]
enum Notation {
    Standard,
    Compact,
}

#[derive(Clone, Copy, PartialEq)]
enum Style {
    Decimal,
    Percent,
}

#[derive(Clone, Copy)]
enum CompactDisplay {
    Short,
    Long,
}

#[derive(Clone, Copy)]
enum RoundingMode {
    HalfEven,
    Trunc,
}

/// How the abbreviated significand's precision is resolved under compact
/// notation. Decided once at formatter construction (§2.1 of the redesign) so
/// the formatting loop never re-derives a "was it set?" boolean.
#[derive(Clone, Copy)]
enum CompactPrecision {
    /// Intl/CLDR compact default: 1–2 significant digits of the significand,
    /// never below 0 fraction digits, trailing zeros trimmed. Identical to
    /// `CompactDecimalFormatter::format_fixed_decimal` for significands ≥ 1.
    SignificantDefault,
    /// Explicit fraction digits requested by the caller. `max == None` means
    /// unbounded (caller passed `maximum_fraction_digits: :unbounded`).
    Fixed { min: u16, max: Option<u16> },
}

#[derive(Clone)]
struct FormatterConfig {
    minimum_integer_digits: u16,
    minimum_fraction_digits: u16,
    // Effective maximum fraction digits; `None` means unbounded. When the
    // caller gives no maximum this is resolved at decode time to
    // `max(min, style default)` (3 for decimal, 0 for percent).
    maximum_fraction_digits: Option<u16>,
    // Whether the caller set maximum_fraction_digits explicitly, as opposed to
    // the resolved default above. Drives validation and the compact default.
    maximum_fraction_digits_set: bool,
    grouping_strategy: GroupingStrategy,
    sign_display: SignDisplay,
    notation: Notation,
    style: Style,
    compact_display: CompactDisplay,
    rounding_mode: RoundingMode,
    // Resolved compact-significand precision. Only consulted under compact
    // notation; the fraction-digit fields above still drive standard/percent.
    compact_precision: CompactPrecision,
}

impl Default for FormatterConfig {
    fn default() -> Self {
        Self {
            minimum_integer_digits: 1,
            minimum_fraction_digits: 0,
            maximum_fraction_digits: Some(3),
            maximum_fraction_digits_set: false,
            grouping_strategy: GroupingStrategy::Auto,
            sign_display: SignDisplay::Auto,
            notation: Notation::Standard,
            style: Style::Decimal,
            compact_display: CompactDisplay::Short,
            rounding_mode: RoundingMode::HalfEven,
            compact_precision: CompactPrecision::SignificantDefault,
        }
    }
}

#[derive(NifMap)]
struct NumberFormatPart {
    #[rustler(map = "type")]
    part_type: Atom,
    value: String,
}

struct CollectedPart {
    start: usize,
    end: usize,
    part: WriteablePart,
}

struct PartsCollector {
    output: String,
    parts: Vec<CollectedPart>,
}

impl PartsCollector {
    fn new() -> Self {
        Self {
            output: String::new(),
            parts: Vec::new(),
        }
    }

    fn into_number_parts(self) -> (String, Vec<CollectedPart>) {
        (self.output, self.parts)
    }
}

impl fmt::Write for PartsCollector {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        self.output.push_str(s);
        Ok(())
    }

    fn write_char(&mut self, c: char) -> fmt::Result {
        self.output.push(c);
        Ok(())
    }
}

impl PartsWrite for PartsCollector {
    type SubPartsWrite = PartsCollector;

    fn with_part(
        &mut self,
        part: WriteablePart,
        mut f: impl FnMut(&mut Self::SubPartsWrite) -> fmt::Result,
    ) -> fmt::Result {
        let start = self.output.len();
        f(self)?;
        let end = self.output.len();
        if start < end {
            self.parts.push(CollectedPart { start, end, part });
        }
        Ok(())
    }
}

pub(crate) fn load(env: Env) -> bool {
    env.register::<NumberFormatterResource>().is_ok()
}

#[rustler::nif]
pub(crate) fn number_formatter_new<'a>(
    env: Env<'a>,
    locale_term: Term<'a>,
    options_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let locale_resource: ResourceArc<LocaleResource> = match locale_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
    };

    let config = match decode_formatter_config(options_term) {
        Ok(config) => config,
        Err(_) => return Ok((atoms::error(), atoms::invalid_options()).encode(env)),
    };

    // Percent is a distinct ICU4X formatter and has no compact variant at the
    // pinned rev, so the two are mutually exclusive.
    if config.style == Style::Percent && config.notation == Notation::Compact {
        return Ok((atoms::error(), atoms::invalid_options()).encode(env));
    }

    let mut formatter_options = DecimalFormatterOptions::default();
    formatter_options.grouping_strategy = Some(config.grouping_strategy);

    let formatter = match (config.style, config.notation) {
        (Style::Percent, _) => {
            match PercentFormatter::try_new(locale_resource.0.clone().into(), Default::default()) {
                Ok(formatter) => FormatterKind::Percent(Box::new(formatter)),
                Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
            }
        }
        (Style::Decimal, Notation::Standard) => {
            match DecimalFormatter::try_new(locale_resource.0.clone().into(), formatter_options) {
                Ok(formatter) => FormatterKind::Standard(formatter),
                Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
            }
        }
        (Style::Decimal, Notation::Compact) => {
            let compact_options = CompactDecimalFormatterOptions::from(formatter_options);
            let prefs = locale_resource.0.clone().into();
            let result = match config.compact_display {
                CompactDisplay::Short => {
                    CompactDecimalFormatter::try_new_short(prefs, compact_options)
                }
                CompactDisplay::Long => {
                    CompactDecimalFormatter::try_new_long(prefs, compact_options)
                }
            };
            match result {
                Ok(formatter) => FormatterKind::Compact(Box::new(formatter)),
                Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
            }
        }
    };

    let resource = NumberFormatterResource { formatter, config };
    Ok((atoms::ok(), ResourceArc::new(resource)).encode(env))
}

#[rustler::nif]
pub(crate) fn number_format<'a>(
    env: Env<'a>,
    formatter_term: Term<'a>,
    number_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let formatter_resource: ResourceArc<NumberFormatterResource> = match formatter_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_formatter()).encode(env)),
    };

    let mut decimal = match term_to_decimal(number_term) {
        Ok(decimal) => decimal,
        Err(_) => return Ok((atoms::error(), atoms::invalid_number()).encode(env)),
    };

    match &formatter_resource.formatter {
        FormatterKind::Standard(formatter) => {
            apply_config(&mut decimal, &formatter_resource.config);
            let formatted = formatter.format(&decimal).to_string();
            Ok((atoms::ok(), formatted).encode(env))
        }
        FormatterKind::Compact(formatter) => {
            decimal.apply_sign_display(formatter_resource.config.sign_display);
            match format_compact(formatter, &decimal, &formatter_resource.config) {
                Ok((formatted, _displayed)) => Ok((atoms::ok(), formatted).encode(env)),
                Err(_) => Ok((atoms::error(), atoms::invalid_number()).encode(env)),
            }
        }
        FormatterKind::Percent(formatter) => {
            // Intl semantics: the input is a ratio, so scale by 100 (0.5 -> 50%).
            // The percent default of 0 fraction digits is already resolved into
            // `maximum_fraction_digits` at construction time.
            decimal.multiply_pow10(2);
            apply_config(&mut decimal, &formatter_resource.config);
            let formatted = formatter.format(&decimal).to_string();
            Ok((atoms::ok(), formatted).encode(env))
        }
    }
}

#[rustler::nif]
pub(crate) fn number_format_compact<'a>(
    env: Env<'a>,
    formatter_term: Term<'a>,
    number_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let formatter_resource: ResourceArc<NumberFormatterResource> = match formatter_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_formatter()).encode(env)),
    };

    let formatter = match &formatter_resource.formatter {
        FormatterKind::Compact(formatter) => formatter,
        FormatterKind::Standard(_) | FormatterKind::Percent(_) => {
            return Ok((atoms::error(), atoms::invalid_formatter()).encode(env))
        }
    };

    let mut decimal = match term_to_decimal(number_term) {
        Ok(decimal) => decimal,
        Err(_) => return Ok((atoms::error(), atoms::invalid_number()).encode(env)),
    };

    decimal.apply_sign_display(formatter_resource.config.sign_display);

    match format_compact(formatter, &decimal, &formatter_resource.config) {
        Ok((formatted, displayed_value)) => {
            Ok((atoms::ok(), (formatted, displayed_value)).encode(env))
        }
        Err(_) => Ok((atoms::error(), atoms::invalid_number()).encode(env)),
    }
}

/// Format a decimal in compact notation and report the exact numeric value the
/// abbreviated string represents.
///
/// The returned string pair is `(formatted, displayed_value)` where
/// `displayed_value` is the exact numeric the compact string stands for, as a
/// plain decimal string (no grouping, no explicit `+`) — the Elixir side parses
/// it into a `Decimal`. Callers compare it against the input to decide whether
/// to append a localised "+".
///
/// Precision follows `config.compact_precision` (§2.1): the Intl/CLDR
/// significant-digit default when the caller gave no fraction options, or an
/// explicit fraction-digit range otherwise. `config.rounding_mode` is purely
/// directional — half-even rounds, trunc floors toward zero — and applies at
/// whichever precision is in effect. Truncation toward zero never overstates a
/// non-negative value's magnitude (`6_718` at 0 digits -> `"6K"`, never `"7K"`).
///
/// A single path picks the locale's compact exponent for the value's magnitude,
/// rounds/truncates the significand ourselves, then hands ICU4X a fully-resolved
/// [`CompactDecimal`] via `format_compact_decimal` (which performs no rounding of
/// its own and errors on a significand/exponent mismatch). Half-even rounding can
/// carry the significand across a magnitude boundary (`999.95 → 1000`); the loop
/// re-picks the exponent and re-rounds from the original value until stable
/// (`999_950` at 1 digit -> `"1M"`), which keeps `format_compact_decimal` from
/// ever seeing an inconsistent significand/exponent pair.
fn format_compact(
    formatter: &CompactDecimalFormatter,
    value: &FixedDecimal,
    config: &FormatterConfig,
) -> Result<(String, String), ()> {
    let magnitude = value.absolute.nonzero_magnitude_start();
    let mut exponent = formatter.compact_exponent_for_magnitude(magnitude);

    // Resolve the significand at the current exponent, re-picking the exponent
    // if rounding carried across a magnitude boundary. Trunc never carries;
    // half-even carries at most once, so this converges within two iterations
    // (the third is a safety stop).
    let mut significand = value.clone();
    for _ in 0..3 {
        // Restart from the original value each pass: rounding an
        // already-rounded significand can compound error.
        significand = value.clone();
        significand.multiply_pow10(-i16::from(exponent));

        match config.compact_precision {
            CompactPrecision::SignificantDefault => {
                // 2 significant digits: one fractional digit when the
                // significand has a single integer digit, none otherwise,
                // floored at 0. Matches `format_fixed_decimal` for
                // significands ≥ 1 (sub-1 significands keep 2 digits, per Intl).
                let sig_magnitude = significand.absolute.nonzero_magnitude_start();
                let digits = (1 - sig_magnitude).max(0);
                round_significand(&mut significand, digits, config.rounding_mode);
            }
            CompactPrecision::Fixed { max: Some(max), .. } => {
                if let Ok(digits) = i16::try_from(max) {
                    round_significand(&mut significand, digits, config.rounding_mode);
                }
            }
            // Unbounded maximum: emit every digit, no rounding step.
            CompactPrecision::Fixed { max: None, .. } => {}
        }

        let new_magnitude = significand.absolute.nonzero_magnitude_start() + i16::from(exponent);
        let new_exponent = formatter.compact_exponent_for_magnitude(new_magnitude);
        if new_exponent == exponent {
            break;
        }
        exponent = new_exponent;
    }

    significand.absolute.trim_end();

    if let CompactPrecision::Fixed { min, .. } = config.compact_precision {
        if let Ok(digits) = i16::try_from(min) {
            if digits > 0 {
                significand.absolute.pad_end(-digits);
            }
        }
    }

    let compact = CompactDecimal::from_significand_and_exponent(significand, exponent);
    let formatted = formatter.format_compact_decimal(&compact).map_err(|_| ())?;

    Ok((formatted.to_string(), displayed_value(&compact)))
}

/// Round the compact significand in place at `digits` fraction digits, honouring
/// the rounding direction: half-even rounds to nearest, trunc floors toward zero.
fn round_significand(significand: &mut FixedDecimal, digits: i16, rounding_mode: RoundingMode) {
    match rounding_mode {
        RoundingMode::Trunc => significand.trunc(-digits),
        RoundingMode::HalfEven => significand.round(-digits),
    }
}

/// Recover the exact numeric a [`CompactDecimal`] represents (significand scaled
/// back up by its exponent), rendered without grouping. A leading explicit `+`
/// (from a `sign_display` setting) is stripped so the value parses cleanly as a
/// `Decimal` on the Elixir side.
fn displayed_value(compact: &CompactDecimal) -> String {
    let mut value = compact.significand().clone();
    value.multiply_pow10(i16::from(compact.exponent()));
    let rendered = value.to_string();
    rendered
        .strip_prefix('+')
        .map(str::to_string)
        .unwrap_or(rendered)
}

#[rustler::nif]
pub(crate) fn number_format_to_parts<'a>(
    env: Env<'a>,
    formatter_term: Term<'a>,
    number_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let formatter_resource: ResourceArc<NumberFormatterResource> = match formatter_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_formatter()).encode(env)),
    };

    let formatter = match &formatter_resource.formatter {
        FormatterKind::Standard(formatter) => formatter,
        // Parts output is only meaningful for the plain decimal formatter.
        FormatterKind::Compact(_) | FormatterKind::Percent(_) => {
            return Ok((atoms::error(), atoms::invalid_options()).encode(env))
        }
    };

    let mut decimal = match term_to_decimal(number_term) {
        Ok(decimal) => decimal,
        Err(_) => return Ok((atoms::error(), atoms::invalid_number()).encode(env)),
    };

    apply_config(&mut decimal, &formatter_resource.config);

    let formatted = formatter.format(&decimal);
    let mut collector = PartsCollector::new();
    if formatted.write_to_parts(&mut collector).is_err() {
        return Ok((atoms::error(), atoms::invalid_number()).encode(env));
    }
    let (output, collected_parts) = collector.into_number_parts();
    let mut parts = Vec::with_capacity(collected_parts.len());

    for collected in collected_parts {
        if let Some(atom) = part_atom(collected.part) {
            if let Some(slice) = output.get(collected.start..collected.end) {
                parts.push(NumberFormatPart {
                    part_type: atom,
                    value: slice.to_string(),
                });
            }
        }
    }

    Ok((atoms::ok(), parts).encode(env))
}

fn decode_formatter_config<'a>(term: Term<'a>) -> Result<FormatterConfig, ()> {
    if term.get_type() != TermType::Map {
        if let Ok(atom_name) = term.atom_to_string() {
            if atom_name == "nil" {
                return Ok(FormatterConfig::default());
            }
        }
        return Err(());
    }

    let mut config = FormatterConfig::default();
    let mut minimum_fraction_digits_set = false;
    let iter = MapIterator::new(term).ok_or(())?;

    for (key_term, value_term) in iter {
        let key: Atom = key_term.decode().map_err(|_| ())?;
        if key == atoms::minimum_integer_digits() {
            let value: i64 = value_term.decode().map_err(|_| ())?;
            if value < 1 || value > i64::from(i16::MAX) {
                return Err(());
            }
            config.minimum_integer_digits = value as u16;
        } else if key == atoms::minimum_fraction_digits() {
            minimum_fraction_digits_set = true;
            let value: i64 = value_term.decode().map_err(|_| ())?;
            if value < 0 || value > i64::from(i16::MAX) {
                return Err(());
            }
            config.minimum_fraction_digits = value as u16;
        } else if key == atoms::maximum_fraction_digits() {
            config.maximum_fraction_digits_set = true;

            if value_term.get_type() == TermType::Atom {
                if let Ok(atom_name) = value_term.atom_to_string() {
                    if atom_name == "unbounded" {
                        config.maximum_fraction_digits = None;
                        continue;
                    }
                }
                return Err(());
            }

            let value: i64 = value_term.decode().map_err(|_| ())?;
            if value < 0 || value > i64::from(i16::MAX) {
                return Err(());
            }
            config.maximum_fraction_digits = Some(value as u16);
        } else if key == atoms::grouping() {
            let value: Atom = value_term.decode().map_err(|_| ())?;
            config.grouping_strategy = match value {
                _ if value == atoms::auto() => GroupingStrategy::Auto,
                _ if value == atoms::always() => GroupingStrategy::Always,
                _ if value == atoms::min2() => GroupingStrategy::Min2,
                _ if value == atoms::never() => GroupingStrategy::Never,
                _ => return Err(()),
            };
        } else if key == atoms::sign_display() {
            let value: Atom = value_term.decode().map_err(|_| ())?;
            config.sign_display = match value {
                _ if value == atoms::auto() => SignDisplay::Auto,
                _ if value == atoms::always() => SignDisplay::Always,
                _ if value == atoms::never() => SignDisplay::Never,
                _ if value == atoms::except_zero() => SignDisplay::ExceptZero,
                _ if value == atoms::negative() => SignDisplay::Negative,
                _ => return Err(()),
            };
        } else if key == atoms::style() {
            let value: Atom = value_term.decode().map_err(|_| ())?;
            config.style = match value {
                _ if value == atoms::decimal() => Style::Decimal,
                _ if value == atoms::percent() => Style::Percent,
                _ => return Err(()),
            };
        } else if key == atoms::notation() {
            let value: Atom = value_term.decode().map_err(|_| ())?;
            config.notation = match value {
                _ if value == atoms::standard() => Notation::Standard,
                _ if value == atoms::compact() => Notation::Compact,
                _ => return Err(()),
            };
        } else if key == atoms::compact_display() {
            let value: Atom = value_term.decode().map_err(|_| ())?;
            config.compact_display = match value {
                _ if value == atoms::short() => CompactDisplay::Short,
                _ if value == atoms::long() => CompactDisplay::Long,
                _ => return Err(()),
            };
        } else if key == atoms::rounding_mode() {
            let value: Atom = value_term.decode().map_err(|_| ())?;
            config.rounding_mode = match value {
                _ if value == atoms::half_even() => RoundingMode::HalfEven,
                _ if value == atoms::trunc() => RoundingMode::Trunc,
                _ => return Err(()),
            };
        } else {
            return Err(());
        }
    }

    // Validation: only when the caller explicitly provided both bounds and the
    // maximum is below the minimum (§2.1). An unset maximum never conflicts —
    // it is resolved via `max(min, default)` below.
    if config.maximum_fraction_digits_set && minimum_fraction_digits_set {
        if let Some(max) = config.maximum_fraction_digits {
            if max < config.minimum_fraction_digits {
                return Err(());
            }
        }
    }

    // Resolve the effective maximum when the caller gave none. Mirrors
    // ECMA-402 `SetNumberFormatDigitOptions`: `mxfd = max(mnfd, mxfdDefault)`,
    // where the default is 3 for decimal style and 0 for percent. This is what
    // standard/percent rounding in `apply_config` uses, and what the compact
    // resolution below reads — a min-only request keeps its real digits
    // (`minimum_fraction_digits: 5` shows 5 digits, not 3 rounded + 2 zeros).
    if !config.maximum_fraction_digits_set {
        let default_max: u16 = match config.style {
            Style::Decimal => 3,
            Style::Percent => 0,
        };
        config.maximum_fraction_digits = Some(config.minimum_fraction_digits.max(default_max));
    }

    // Resolve the compact-significand precision once (§2.1): neither bound
    // given ⇒ significant-digit default; otherwise the fixed fraction-digit
    // range resolved above, with an explicit `:unbounded` meaning no maximum.
    config.compact_precision =
        if !config.maximum_fraction_digits_set && !minimum_fraction_digits_set {
            CompactPrecision::SignificantDefault
        } else {
            CompactPrecision::Fixed {
                min: config.minimum_fraction_digits,
                max: config.maximum_fraction_digits,
            }
        };

    Ok(config)
}

pub(crate) fn term_to_decimal<'a>(term: Term<'a>) -> Result<FixedDecimal, ()> {
    if let Ok(value) = term.decode::<i64>() {
        return Ok(FixedDecimal::from(value));
    }

    if let Ok(value) = term.decode::<BigInt>() {
        let string_value = value.to_string();
        return FixedDecimal::try_from_str(&string_value).map_err(|_| ());
    }

    if let Ok(value) = term.decode::<f64>() {
        if !value.is_finite() {
            return Err(());
        }
        return FixedDecimal::try_from_f64(value, FloatPrecision::RoundTrip).map_err(|_| ());
    }

    // Try decoding as %Decimal{sign: 1|-1, coef: integer, exp: integer}
    if term.get_type() == TermType::Map {
        return try_decode_decimal_struct(term).ok_or(());
    }

    Err(())
}

/// Decode an Elixir `%Decimal{sign: sign, coef: coef, exp: exp}` struct.
/// The number represented is `sign * coef * 10^exp`.
fn try_decode_decimal_struct<'a>(term: Term<'a>) -> Option<FixedDecimal> {
    let iter = MapIterator::new(term)?;

    let mut sign: Option<i64> = None;
    let mut coef_term: Option<Term<'a>> = None;
    let mut exp_val: Option<i64> = None;

    for (key_term, value_term) in iter {
        let key: Atom = key_term.decode().ok()?;
        if key == atoms::sign() {
            sign = Some(value_term.decode().ok()?);
        } else if key == atoms::coef() {
            coef_term = Some(value_term);
        } else if key == atoms::exp() {
            exp_val = Some(value_term.decode().ok()?);
        }
    }

    let sign = sign?;
    let coef_term = coef_term?;
    let exp = exp_val?;
    let exp_i16 = i16::try_from(exp).ok()?;

    // Decode coefficient as i64, falling back to BigInt string for large values.
    // Atoms like :NaN / :inf will fail both decodes and return None.
    let mut decimal = if let Ok(coef) = coef_term.decode::<i64>() {
        FixedDecimal::from(coef)
    } else if let Ok(coef) = coef_term.decode::<BigInt>() {
        FixedDecimal::try_from_str(&coef.to_string()).ok()?
    } else {
        return None;
    };

    decimal.multiply_pow10(exp_i16);

    if sign < 0 {
        decimal.set_sign(fixed_decimal::Sign::Negative);
    }

    Some(decimal)
}

fn apply_config(decimal: &mut FixedDecimal, config: &FormatterConfig) {
    if let Some(max_fraction_digits) = config.maximum_fraction_digits {
        if let Ok(position) = i16::try_from(max_fraction_digits) {
            // Honour the rounding direction (§2.3): trunc floors toward zero,
            // half-even rounds to nearest. Shared with percent style.
            match config.rounding_mode {
                RoundingMode::Trunc => decimal.trunc(-position),
                RoundingMode::HalfEven => decimal.round(-position),
            }
        }
    }

    if config.minimum_integer_digits > 0 {
        if let Ok(position) = i16::try_from(config.minimum_integer_digits) {
            decimal.pad_start(position);
        }
    }

    if config.minimum_fraction_digits > 0 {
        if let Ok(position) = i16::try_from(config.minimum_fraction_digits) {
            decimal.pad_end(-position);
        }
    }

    decimal.apply_sign_display(config.sign_display);
}

fn part_atom(part: WriteablePart) -> Option<Atom> {
    if part == parts::INTEGER {
        Some(atoms::integer())
    } else if part == parts::DECIMAL {
        Some(atoms::decimal())
    } else if part == parts::FRACTION {
        Some(atoms::fraction())
    } else if part == parts::GROUP {
        Some(atoms::group())
    } else if part == parts::PLUS_SIGN {
        Some(atoms::plus_sign())
    } else if part == parts::MINUS_SIGN {
        Some(atoms::minus_sign())
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use icu::locale::Locale;

    fn compact_formatter(tag: &str) -> CompactDecimalFormatter {
        let locale: Locale = tag.parse().unwrap();
        CompactDecimalFormatter::try_new_short(locale.into(), Default::default()).unwrap()
    }

    /// The `SignificantDefault` precision must reproduce ICU4X's own
    /// `format_fixed_decimal` for every value whose abbreviated significand is
    /// ≥ 1 (i.e. every value ≥ 1). Sub-1 significands intentionally diverge
    /// (they keep 2 significant digits, Intl-style) and are excluded here. This
    /// pins the significand rule now that we no longer delegate to
    /// `format_fixed_decimal`.
    #[test]
    fn significant_default_matches_format_fixed_decimal() {
        let values = [
            "0",
            "1",
            "999",
            "1000",
            "1050",
            "1650",
            "1750",
            "1950",
            "6718",
            "6780",
            "9999",
            "12000",
            "15000",
            "15400",
            "194438",
            "999499",
            "999500",
            "999999",
            "1000000",
            "9999500",
            "1172700",
            "-1172700",
            "9223372036854775807",
        ];
        let config = FormatterConfig::default(); // SignificantDefault, half-even.
        for tag in ["en", "ja", "ru", "hi", "de"] {
            let formatter = compact_formatter(tag);
            for v in values {
                let value = FixedDecimal::try_from_str(v).unwrap();
                let expected = formatter.format_fixed_decimal(&value).to_string();
                let (actual, _) = format_compact(&formatter, &value, &config).unwrap();
                assert_eq!(
                    actual, expected,
                    "locale {tag}, value {v}: SignificantDefault != format_fixed_decimal"
                );
            }
        }
    }

    /// Half-even carries across a magnitude boundary must be absorbed by the
    /// carry loop, never surfaced as a `format_compact_decimal` error (§2.2).
    #[test]
    fn half_even_boundary_carry_resolves() {
        let formatter = compact_formatter("en");
        let mut config = FormatterConfig::default();
        config.compact_precision = CompactPrecision::Fixed {
            min: 0,
            max: Some(1),
        };
        let value = FixedDecimal::try_from_str("999950").unwrap();
        let (formatted, displayed) = format_compact(&formatter, &value, &config).unwrap();
        assert_eq!(formatted, "1M");
        assert_eq!(displayed, "1000000");
    }
}
