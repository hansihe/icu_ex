use std::convert::TryFrom;
use std::fmt;

use fixed_decimal::Decimal as FixedDecimal;
use fixed_decimal::{CompactDecimal, FloatPrecision, SignDisplay};
use icu::decimal::options::{DecimalFormatterOptions, GroupingStrategy};
use icu::decimal::{parts, DecimalFormatter};
use icu::experimental::compactdecimal::{CompactDecimalFormatter, CompactDecimalFormatterOptions};
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

/// Either a plain decimal formatter or a compact (abbreviated) one.
///
/// The compact formatter carries the same locale/grouping configuration but is
/// a distinct ICU4X type, so it is selected once at construction time.
enum FormatterKind {
    Standard(DecimalFormatter),
    // Boxed: CompactDecimalFormatter is substantially larger than DecimalFormatter.
    Compact(Box<CompactDecimalFormatter>),
}

#[derive(Clone, Copy, PartialEq)]
enum Notation {
    Standard,
    Compact,
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

#[derive(Clone)]
struct FormatterConfig {
    minimum_integer_digits: u16,
    minimum_fraction_digits: u16,
    maximum_fraction_digits: Option<u16>,
    grouping_strategy: GroupingStrategy,
    sign_display: SignDisplay,
    notation: Notation,
    compact_display: CompactDisplay,
    rounding_mode: RoundingMode,
}

impl Default for FormatterConfig {
    fn default() -> Self {
        Self {
            minimum_integer_digits: 1,
            minimum_fraction_digits: 0,
            maximum_fraction_digits: Some(3),
            grouping_strategy: GroupingStrategy::Auto,
            sign_display: SignDisplay::Auto,
            notation: Notation::Standard,
            compact_display: CompactDisplay::Short,
            rounding_mode: RoundingMode::HalfEven,
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

    let mut formatter_options = DecimalFormatterOptions::default();
    formatter_options.grouping_strategy = Some(config.grouping_strategy);

    let formatter = match config.notation {
        Notation::Standard => {
            match DecimalFormatter::try_new(locale_resource.0.clone().into(), formatter_options) {
                Ok(formatter) => FormatterKind::Standard(formatter),
                Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
            }
        }
        Notation::Compact => {
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
            match format_compact(formatter, &decimal, formatter_resource.config.rounding_mode) {
                Ok((formatted, _displayed)) => Ok((atoms::ok(), formatted).encode(env)),
                Err(_) => Ok((atoms::error(), atoms::invalid_number()).encode(env)),
            }
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
        FormatterKind::Standard(_) => {
            return Ok((atoms::error(), atoms::invalid_formatter()).encode(env))
        }
    };

    let mut decimal = match term_to_decimal(number_term) {
        Ok(decimal) => decimal,
        Err(_) => return Ok((atoms::error(), atoms::invalid_number()).encode(env)),
    };

    decimal.apply_sign_display(formatter_resource.config.sign_display);

    match format_compact(formatter, &decimal, formatter_resource.config.rounding_mode) {
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
/// `displayed_value` is the plain integer (no grouping, no explicit `+`) that
/// the compact string stands for. Callers compare it against the exact input to
/// decide whether to append a localised "+".
///
/// With [`RoundingMode::HalfEven`] we defer to ICU4X's own rounding and read the
/// resolved [`CompactDecimal`] back out. With [`RoundingMode::Trunc`] we pick the
/// locale's compact exponent for the value's magnitude, truncate the significand
/// towards zero to whole units ourselves, and hand ICU4X a fully-resolved
/// [`CompactDecimal`] via `format_compact_decimal`, which performs no rounding.
fn format_compact(
    formatter: &CompactDecimalFormatter,
    value: &FixedDecimal,
    rounding_mode: RoundingMode,
) -> Result<(String, String), ()> {
    let (formatted, compact) = match rounding_mode {
        RoundingMode::HalfEven => {
            let formatted = formatter.format_fixed_decimal(value);
            (
                formatted.to_string(),
                formatted.get_compact_decimal().clone(),
            )
        }
        RoundingMode::Trunc => {
            let magnitude = value.absolute.nonzero_magnitude_start();
            let exponent = formatter.compact_exponent_for_magnitude(magnitude);

            let mut significand = value.clone();
            significand.multiply_pow10(-i16::from(exponent));
            // Truncate towards zero to whole units so the abbreviation never
            // overstates the value (6,718 -> "6K", never "7K").
            significand.trunc(0);
            significand.absolute.trim_end();

            let compact = CompactDecimal::from_significand_and_exponent(significand, exponent);
            let formatted = formatter.format_compact_decimal(&compact).map_err(|_| ())?;
            (formatted.to_string(), compact)
        }
    };

    Ok((formatted, displayed_value(&compact)))
}

/// Recover the exact integer a [`CompactDecimal`] represents (significand scaled
/// back up by its exponent), rendered without grouping. A leading explicit `+`
/// (from a `sign_display` setting) is stripped so the value parses as a plain
/// integer on the Elixir side.
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
        FormatterKind::Compact(_) => {
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
            let value: i64 = value_term.decode().map_err(|_| ())?;
            if value < 0 || value > i64::from(i16::MAX) {
                return Err(());
            }
            config.minimum_fraction_digits = value as u16;
        } else if key == atoms::maximum_fraction_digits() {
            if value_term.get_type() == TermType::Atom {
                if let Ok(atom_name) = value_term.atom_to_string() {
                    if atom_name == "nil" {
                        config.maximum_fraction_digits = None;
                        continue;
                    }
                }
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

    if let Some(max) = config.maximum_fraction_digits {
        if max < config.minimum_fraction_digits {
            return Err(());
        }
    }

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
            decimal.round(-position);
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
