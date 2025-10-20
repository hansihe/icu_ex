use std::str::FromStr;

use icu::experimental::displaynames::{
    DisplayNamesOptions, Fallback, LanguageDisplay, LanguageDisplayNames,
    LocaleDisplayNamesFormatter, RegionDisplayNames, ScriptDisplayNames, Style,
    VariantDisplayNames,
};
use icu::locale::subtags::{Language, Region, Script, Variant};
use icu::locale::Locale;
use rustler::types::map::MapIterator;
use rustler::{Atom, Encoder, Env, NifResult, ResourceArc, Term, TermType};

use crate::atoms;
use crate::locale::LocaleResource;

pub(crate) struct DisplayNamesFormatterResource {
    formatter: DisplayNameFormatter,
}

impl rustler::Resource for DisplayNamesFormatterResource {}

enum DisplayNameFormatter {
    Locale(LocaleDisplayNamesFormatter),
    Language(LanguageDisplayNames),
    Region(RegionDisplayNames),
    Script(ScriptDisplayNames),
    Variant(VariantDisplayNames),
}

enum FormatterKind {
    Locale,
    Language,
    Region,
    Script,
    Variant,
}

pub(crate) fn load(env: Env) -> bool {
    env.register::<DisplayNamesFormatterResource>().is_ok()
}

#[rustler::nif]
pub(crate) fn display_names_formatter_new<'a>(
    env: Env<'a>,
    locale_term: Term<'a>,
    kind_term: Term<'a>,
    options_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let locale_resource: ResourceArc<LocaleResource> = match locale_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
    };

    let kind = match decode_kind(kind_term) {
        Ok(kind) => kind,
        Err(_) => return Ok((atoms::error(), atoms::invalid_options()).encode(env)),
    };

    let options = match decode_options(options_term) {
        Ok(options) => options,
        Err(_) => return Ok((atoms::error(), atoms::invalid_options()).encode(env)),
    };

    let formatter = match kind {
        FormatterKind::Locale => {
            LocaleDisplayNamesFormatter::try_new(locale_resource.0.clone().into(), options)
                .map(DisplayNameFormatter::Locale)
        }
        FormatterKind::Language => {
            LanguageDisplayNames::try_new(locale_resource.0.clone().into(), options)
                .map(DisplayNameFormatter::Language)
        }
        FormatterKind::Region => {
            RegionDisplayNames::try_new(locale_resource.0.clone().into(), options)
                .map(DisplayNameFormatter::Region)
        }
        FormatterKind::Script => {
            ScriptDisplayNames::try_new(locale_resource.0.clone().into(), options)
                .map(DisplayNameFormatter::Script)
        }
        FormatterKind::Variant => {
            VariantDisplayNames::try_new(locale_resource.0.clone().into(), options)
                .map(DisplayNameFormatter::Variant)
        }
    };

    let formatter = match formatter {
        Ok(formatter) => formatter,
        Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
    };

    let resource = DisplayNamesFormatterResource { formatter };
    Ok((atoms::ok(), ResourceArc::new(resource)).encode(env))
}

#[rustler::nif]
pub(crate) fn display_names_of<'a>(
    env: Env<'a>,
    formatter_term: Term<'a>,
    value_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let formatter_resource: ResourceArc<DisplayNamesFormatterResource> =
        match formatter_term.decode() {
            Ok(resource) => resource,
            Err(_) => return Ok((atoms::error(), atoms::invalid_formatter()).encode(env)),
        };

    match &formatter_resource.formatter {
        DisplayNameFormatter::Locale(formatter) => {
            let locale = match decode_locale(value_term) {
                Ok(locale) => locale,
                Err(_) => return Ok((atoms::error(), atoms::invalid_options()).encode(env)),
            };

            let display_name = formatter.of(&locale).into_owned();
            Ok((atoms::ok(), display_name).encode(env))
        }
        DisplayNameFormatter::Language(formatter) => {
            let language = match decode_language(value_term) {
                Ok(language) => language,
                Err(_) => return Ok((atoms::error(), atoms::invalid_options()).encode(env)),
            };

            let display_name = formatter.of(language).map(|value| value.to_string());
            Ok((atoms::ok(), display_name).encode(env))
        }
        DisplayNameFormatter::Region(formatter) => {
            let region = match decode_region(value_term) {
                Ok(region) => region,
                Err(_) => return Ok((atoms::error(), atoms::invalid_options()).encode(env)),
            };

            let display_name = formatter.of(region).map(|value| value.to_string());
            Ok((atoms::ok(), display_name).encode(env))
        }
        DisplayNameFormatter::Script(formatter) => {
            let script = match decode_script(value_term) {
                Ok(script) => script,
                Err(_) => return Ok((atoms::error(), atoms::invalid_options()).encode(env)),
            };

            let display_name = formatter.of(script).map(|value| value.to_string());
            Ok((atoms::ok(), display_name).encode(env))
        }
        DisplayNameFormatter::Variant(formatter) => {
            let variant = match decode_variant(value_term) {
                Ok(variant) => variant,
                Err(_) => return Ok((atoms::error(), atoms::invalid_options()).encode(env)),
            };

            let display_name = formatter.of(variant).map(|value| value.to_string());
            Ok((atoms::ok(), display_name).encode(env))
        }
    }
}

fn decode_kind<'a>(term: Term<'a>) -> Result<FormatterKind, ()> {
    let value = if term.get_type() == TermType::Atom {
        term.atom_to_string().map_err(|_| ())?
    } else {
        term.decode::<String>().map_err(|_| ())?
    };

    match value.as_str() {
        "locale" => Ok(FormatterKind::Locale),
        "language" => Ok(FormatterKind::Language),
        "region" => Ok(FormatterKind::Region),
        "script" => Ok(FormatterKind::Script),
        "variant" => Ok(FormatterKind::Variant),
        _ => Err(()),
    }
}

fn decode_options<'a>(term: Term<'a>) -> Result<DisplayNamesOptions, ()> {
    if term.get_type() != TermType::Map {
        if let Ok(atom_name) = term.atom_to_string() {
            if atom_name == "nil" {
                return Ok(DisplayNamesOptions::default());
            }
        }
        return Err(());
    }

    let mut options = DisplayNamesOptions::default();
    let mut iter = MapIterator::new(term).ok_or(())?;

    while let Some((key_term, value_term)) = iter.next() {
        let key = key_term.atom_to_string().map_err(|_| ())?;

        if key == "style" {
            if let Ok(atom_name) = value_term.atom_to_string() {
                if atom_name == "nil" {
                    options.style = None;
                    continue;
                }
            }

            let value: Atom = value_term.decode().map_err(|_| ())?;
            options.style = if value == atoms::narrow() {
                Some(Style::Narrow)
            } else if value == atoms::short() {
                Some(Style::Short)
            } else if value == atoms::long() {
                Some(Style::Long)
            } else if value == atoms::menu() {
                Some(Style::Menu)
            } else {
                return Err(());
            };
        } else if key == "fallback" {
            if let Ok(atom_name) = value_term.atom_to_string() {
                if atom_name == "nil" {
                    options.fallback = Fallback::default();
                    continue;
                }
            }

            let value: Atom = value_term.decode().map_err(|_| ())?;
            options.fallback = if value == atoms::code() {
                Fallback::Code
            } else if value == atoms::none() {
                Fallback::None
            } else {
                return Err(());
            };
        } else if key == "language_display" {
            if let Ok(atom_name) = value_term.atom_to_string() {
                if atom_name == "nil" {
                    options.language_display = LanguageDisplay::default();
                    continue;
                }
            }

            let value: Atom = value_term.decode().map_err(|_| ())?;
            options.language_display = if value == atoms::dialect() {
                LanguageDisplay::Dialect
            } else if value == atoms::standard() {
                LanguageDisplay::Standard
            } else {
                return Err(());
            };
        } else if key == "locale" {
            continue;
        } else {
            if value_term.get_type() != TermType::Atom {
                return Err(());
            }

            if let Ok(atom_name) = value_term.atom_to_string() {
                if atom_name == "nil" {
                    continue;
                }
            }

            return Err(());
        }
    }

    Ok(options)
}

fn decode_locale<'a>(term: Term<'a>) -> Result<Locale, ()> {
    if let Ok(resource) = term.decode::<ResourceArc<LocaleResource>>() {
        return Ok(resource.0.clone());
    }

    let value = term_to_string(term)?;
    value.parse::<Locale>().map_err(|_| ())
}

fn decode_language<'a>(term: Term<'a>) -> Result<Language, ()> {
    let value = term_to_string(term)?;
    Language::from_str(&value).map_err(|_| ())
}

fn decode_region<'a>(term: Term<'a>) -> Result<Region, ()> {
    let value = term_to_string(term)?;
    Region::from_str(&value).map_err(|_| ())
}

fn decode_script<'a>(term: Term<'a>) -> Result<Script, ()> {
    let value = term_to_string(term)?;
    Script::from_str(&value).map_err(|_| ())
}

fn decode_variant<'a>(term: Term<'a>) -> Result<Variant, ()> {
    let value = term_to_string(term)?;
    Variant::from_str(&value).map_err(|_| ())
}

fn term_to_string<'a>(term: Term<'a>) -> Result<String, ()> {
    if term.get_type() == TermType::Atom {
        let atom_name = term.atom_to_string().map_err(|_| ())?;
        if atom_name == "nil" {
            return Err(());
        }
        Ok(atom_name)
    } else {
        term.decode::<String>().map_err(|_| ())
    }
}
