use icu::experimental::dimension::provider::currency::fractions::{
    CurrencyFractionsV1, FractionInfo,
};
use icu_provider::{DataProvider as _, DataRequest, DataResponse};
use rustler::{Encoder, Env, NifResult, Term};
use tinystr::UnvalidatedTinyAsciiStr;

use crate::atoms;

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
        Some(fractions) => Ok(CurrencyFractionData {
            digits: fractions.digits,
            rounding: fractions.rounding,
            cash_digits: fractions.cash_digits.unwrap_or(fractions.digits),
            cash_rounding: fractions.cash_rounding.unwrap_or(fractions.rounding),
        }
        .encode(env)),
        None => Ok((atoms::error(), atoms::invalid_currency()).encode(env)),
    }
}

fn get_currency_fractions_inner(currency: &str) -> Option<FractionInfo> {
    let fractions: DataResponse<CurrencyFractionsV1> =
        icu::experimental::dimension::provider::currency::fractions::Baked
            .load(DataRequest::default())
            .unwrap();

    let curr_triple =
        UnvalidatedTinyAsciiStr::from_utf8_unchecked(currency.as_bytes().try_into().ok()?);

    fractions.payload.get().fractions.get_copied(&curr_triple)
}
