use std::convert::TryFrom;
use std::fmt;

use fixed_decimal::Decimal as FixedDecimal;
use fixed_decimal::{FloatPrecision, SignDisplay};
use icu::decimal::options::{DecimalFormatterOptions, GroupingStrategy};
use icu::decimal::{parts, DecimalFormatter};
use rustler::types::map::MapIterator;
use rustler::types::BigInt;
use rustler::{Atom, Encoder, Env, NifMap, NifResult, ResourceArc, Term, TermType};
use writeable::{Part as WriteablePart, PartsWrite, Writeable};

use crate::atoms;
use crate::locale::LocaleResource;

pub(crate) struct NumberFormatterResource {
    formatter: DecimalFormatter,
    config: FormatterConfig,
}

impl rustler::Resource for NumberFormatterResource {}

#[derive(Clone)]
struct FormatterConfig {
    minimum_integer_digits: u16,
    minimum_fraction_digits: u16,
    maximum_fraction_digits: Option<u16>,
    grouping_strategy: GroupingStrategy,
    sign_display: SignDisplay,
}

impl Default for FormatterConfig {
    fn default() -> Self {
        Self {
            minimum_integer_digits: 1,
            minimum_fraction_digits: 0,
            maximum_fraction_digits: Some(3),
            grouping_strategy: GroupingStrategy::Auto,
            sign_display: SignDisplay::Auto,
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

    let formatter =
        match DecimalFormatter::try_new(locale_resource.0.clone().into(), formatter_options) {
            Ok(formatter) => formatter,
            Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
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

    apply_config(&mut decimal, &formatter_resource.config);

    let formatted = formatter_resource.formatter.format(&decimal).to_string();
    Ok((atoms::ok(), formatted).encode(env))
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

    let mut decimal = match term_to_decimal(number_term) {
        Ok(decimal) => decimal,
        Err(_) => return Ok((atoms::error(), atoms::invalid_number()).encode(env)),
    };

    apply_config(&mut decimal, &formatter_resource.config);

    let formatted = formatter_resource.formatter.format(&decimal);
    let mut collector = PartsCollector::new();
    if let Err(_) = formatted.write_to_parts(&mut collector) {
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
    let mut iter = MapIterator::new(term).ok_or(())?;

    while let Some((key_term, value_term)) = iter.next() {
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
