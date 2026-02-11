use icu::experimental::dimension::currency::formatter::CurrencyFormatter;
use icu::experimental::dimension::currency::long_formatter::LongCurrencyFormatter;
use icu::experimental::dimension::currency::options::{CurrencyFormatterOptions, Width};
use icu::experimental::dimension::currency::CurrencyCode;
use icu::experimental::dimension::provider::currency::fractions::{
    CurrencyFractionsV1, FractionInfo,
};
use icu_provider::{DataProvider as _, DataRequest, DataResponse};
use rustler::types::map::MapIterator;
use rustler::{Atom, Encoder, Env, NifResult, ResourceArc, Term, TermType};
use tinystr::{TinyAsciiStr, UnvalidatedTinyAsciiStr};

use crate::atoms;
use crate::locale::LocaleResource;
use crate::number;

#[derive(rustler::NifMap)]
struct CurrencyFractionData {
    digits: u8,
    rounding: u8,
    cash_digits: u8,
    cash_rounding: u8,
}

#[rustler::nif]
pub(crate) fn currency_fractions<'a>(env: Env<'a>, currency: &str) -> NifResult<Term<'a>> {
    match get_currency_fractions_inner(currency) {
        Some(fractions) => Ok((
            atoms::ok(),
            CurrencyFractionData {
                digits: fractions.digits,
                rounding: fractions.rounding,
                cash_digits: fractions.cash_digits.unwrap_or(fractions.digits),
                cash_rounding: fractions.cash_rounding.unwrap_or(fractions.rounding),
            },
        )
            .encode(env)),
        None => Ok((atoms::error(), atoms::invalid_currency()).encode(env)),
    }
}

fn get_currency_fractions_inner(currency: &str) -> Option<FractionInfo> {
    let bytes: [u8; 3] = currency.as_bytes().try_into().ok()?;
    let curr_triple = UnvalidatedTinyAsciiStr::from_utf8_unchecked(bytes);

    let fractions: DataResponse<CurrencyFractionsV1> =
        icu::experimental::dimension::provider::currency::fractions::Baked
            .load(DataRequest::default())
            .unwrap();

    let data = fractions.payload.get();
    Some(
        data.fractions
            .get_copied(&curr_triple)
            .unwrap_or(data.default),
    )
}

// Currency formatter

enum CurrencyFormatterKind {
    Standard(CurrencyFormatter),
    Long(LongCurrencyFormatter),
}

pub(crate) struct CurrencyFormatterResource {
    formatter: CurrencyFormatterKind,
    currency_code: CurrencyCode,
}

impl rustler::Resource for CurrencyFormatterResource {}

pub(crate) fn load(env: Env) -> bool {
    env.register::<CurrencyFormatterResource>().is_ok()
}

#[rustler::nif]
pub(crate) fn currency_formatter_new<'a>(
    env: Env<'a>,
    locale_term: Term<'a>,
    currency_code_str: &str,
    options_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let locale_resource: ResourceArc<LocaleResource> = match locale_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
    };

    let tiny_str: TinyAsciiStr<3> = match TinyAsciiStr::try_from_str(currency_code_str) {
        Ok(s) => s,
        Err(_) => return Ok((atoms::error(), atoms::invalid_currency()).encode(env)),
    };
    let currency_code = CurrencyCode(tiny_str);

    let width = decode_width(options_term)?;

    let formatter = match width {
        WidthOption::Short => {
            let mut opts = CurrencyFormatterOptions::default();
            opts.width = Width::Short;
            match CurrencyFormatter::try_new(locale_resource.0.clone().into(), opts) {
                Ok(f) => CurrencyFormatterKind::Standard(f),
                Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
            }
        }
        WidthOption::Narrow => {
            let mut opts = CurrencyFormatterOptions::default();
            opts.width = Width::Narrow;
            match CurrencyFormatter::try_new(locale_resource.0.clone().into(), opts) {
                Ok(f) => CurrencyFormatterKind::Standard(f),
                Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
            }
        }
        WidthOption::Long => {
            match LongCurrencyFormatter::try_new(locale_resource.0.clone().into(), &currency_code) {
                Ok(f) => CurrencyFormatterKind::Long(f),
                Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
            }
        }
    };

    let resource = CurrencyFormatterResource {
        formatter,
        currency_code,
    };
    Ok((atoms::ok(), ResourceArc::new(resource)).encode(env))
}

#[rustler::nif]
pub(crate) fn currency_format<'a>(
    env: Env<'a>,
    formatter_term: Term<'a>,
    number_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let resource: ResourceArc<CurrencyFormatterResource> = match formatter_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_formatter()).encode(env)),
    };

    let decimal = match number::term_to_decimal(number_term) {
        Ok(decimal) => decimal,
        Err(_) => return Ok((atoms::error(), atoms::invalid_number()).encode(env)),
    };

    let formatted = match &resource.formatter {
        CurrencyFormatterKind::Standard(f) => {
            f.format_fixed_decimal(&decimal, resource.currency_code)
                .to_string()
        }
        CurrencyFormatterKind::Long(f) => {
            f.format_fixed_decimal(&decimal, resource.currency_code)
                .to_string()
        }
    };

    Ok((atoms::ok(), formatted).encode(env))
}

enum WidthOption {
    Short,
    Narrow,
    Long,
}

fn decode_width<'a>(term: Term<'a>) -> NifResult<WidthOption> {
    if term.get_type() != TermType::Map {
        if let Ok(atom_name) = term.atom_to_string() {
            if atom_name == "nil" {
                return Ok(WidthOption::Short);
            }
        }
        return Ok(WidthOption::Short);
    }

    let mut width = WidthOption::Short;
    let iter = MapIterator::new(term).ok_or(rustler::Error::BadArg)?;

    for (key_term, value_term) in iter {
        let key: Atom = key_term.decode().map_err(|_| rustler::Error::BadArg)?;
        if key == atoms::width() {
            let value: Atom = value_term.decode().map_err(|_| rustler::Error::BadArg)?;
            width = if value == atoms::short() {
                WidthOption::Short
            } else if value == atoms::narrow() {
                WidthOption::Narrow
            } else if value == atoms::long() {
                WidthOption::Long
            } else {
                return Err(rustler::Error::BadArg);
            };
        }
    }

    Ok(width)
}
