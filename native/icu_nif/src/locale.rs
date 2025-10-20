use std::collections::HashMap;

use icu::locale::fallback::LocaleFallbackConfig;
use icu::locale::{subtags::Language, LocaleExpander};
use icu::locale::{Locale, LocaleFallbacker};
use rustler::{Encoder, Env, NifResult, NifStruct, ResourceArc, Term};

use crate::atoms;

pub(crate) struct LocaleResource(pub Locale);

impl rustler::Resource for LocaleResource {}

#[derive(NifStruct)]
#[module = "Icu.LanguageTag.Components"]
struct LanguageTagComponents {
    language: Option<String>,
    script: Option<String>,
    region: Option<String>,
    variants: Vec<String>,
}

pub(crate) fn load(env: Env) -> bool {
    env.register::<LocaleResource>().is_ok()
}

#[rustler::nif]
pub(crate) fn locale_from_string<'a>(env: Env<'a>, locale_string: String) -> NifResult<Term<'a>> {
    match locale_string.parse::<Locale>() {
        Ok(locale) => {
            let resource = ResourceArc::new(LocaleResource(locale));
            Ok((atoms::ok(), resource).encode(env))
        }
        Err(_) => Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
    }
}

#[rustler::nif]
pub(crate) fn locale_to_string<'a>(env: Env<'a>, resource_term: Term<'a>) -> NifResult<Term<'a>> {
    let resource: ResourceArc<LocaleResource> = match resource_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_resource()).encode(env)),
    };

    let locale_string = resource.0.to_string();
    Ok((atoms::ok(), locale_string).encode(env))
}

#[rustler::nif]
pub(crate) fn locale_get_components<'a>(
    env: Env<'a>,
    resource_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let resource: ResourceArc<LocaleResource> = match resource_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_resource()).encode(env)),
    };

    let langid = resource.0.id.clone();

    let language = if langid.language == Language::UNKNOWN {
        None
    } else {
        Some(langid.language.to_string())
    };

    let script = langid.script.map(|script| script.to_string());
    let region = langid.region.map(|region| region.to_string());
    let variants = langid
        .variants
        .iter()
        .map(|variant| variant.to_string())
        .collect();

    let components = LanguageTagComponents {
        language,
        script,
        region,
        variants,
    };

    Ok((atoms::ok(), components).encode(env))
}

#[rustler::nif]
pub(crate) fn locale_maximize<'a>(env: Env<'a>, resource_term: Term<'a>) -> NifResult<Term<'a>> {
    let resource: ResourceArc<LocaleResource> = match resource_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_resource()).encode(env)),
    };

    let lc = LocaleExpander::new_common();

    let mut locale = resource.0.clone();
    match lc.maximize(&mut locale.id) {
        icu::locale::TransformResult::Modified => {
            Ok((atoms::modified(), ResourceArc::new(LocaleResource(locale))).encode(env))
        }
        icu::locale::TransformResult::Unmodified => Ok((atoms::unmodified(), resource).encode(env)),
    }
}

#[rustler::nif]
pub(crate) fn locale_minimize<'a>(env: Env<'a>, resource_term: Term<'a>) -> NifResult<Term<'a>> {
    let resource: ResourceArc<LocaleResource> = match resource_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_resource()).encode(env)),
    };

    let lc = LocaleExpander::new_common();

    let mut locale = resource.0.clone();
    match lc.minimize(&mut locale.id) {
        icu::locale::TransformResult::Modified => {
            Ok((atoms::modified(), ResourceArc::new(LocaleResource(locale))).encode(env))
        }
        icu::locale::TransformResult::Unmodified => Ok((atoms::unmodified(), resource).encode(env)),
    }
}

#[rustler::nif]
pub(crate) fn locale_minimize_favor_script<'a>(
    env: Env<'a>,
    resource_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let resource: ResourceArc<LocaleResource> = match resource_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_resource()).encode(env)),
    };

    let lc = LocaleExpander::new_common();

    let mut locale = resource.0.clone();
    match lc.minimize_favor_script(&mut locale.id) {
        icu::locale::TransformResult::Modified => {
            Ok((atoms::modified(), ResourceArc::new(LocaleResource(locale))).encode(env))
        }
        icu::locale::TransformResult::Unmodified => Ok((atoms::unmodified(), resource).encode(env)),
    }
}

#[rustler::nif]
pub(crate) fn locale_fallbacks<'a>(env: Env<'a>, resource_term: Term<'a>) -> NifResult<Term<'a>> {
    let resource: ResourceArc<LocaleResource> = match resource_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_resource()).encode(env)),
    };

    let fallbacker = LocaleFallbacker::new();
    let config = LocaleFallbackConfig::default();

    let mut fallback_iterator = fallbacker
        .for_config(config)
        .fallback_for(resource.0.clone().into());

    let mut fallbacks = vec![];
    while !fallback_iterator.get().is_unknown() {
        let data_locale = fallback_iterator.get().clone();
        let locale = data_locale.into_locale();
        let resource = ResourceArc::new(LocaleResource(locale));
        fallbacks.push(resource);
        fallback_iterator.step();
    }

    Ok((atoms::ok(), fallbacks).encode(env))
}

#[rustler::nif]
pub(crate) fn locale_match_gettext<'a>(
    env: Env<'a>,
    resource_term: Term<'a>,
    available: Vec<String>,
) -> NifResult<Term<'a>> {
    let resource: ResourceArc<LocaleResource> = match resource_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_resource()).encode(env)),
    };

    let fallbacker = LocaleFallbacker::new();
    let config = LocaleFallbackConfig::default();

    let available_norm: HashMap<String, &str> = available
        .iter()
        .map(|v| (v.replace("_", "-"), &**v))
        .collect();

    let mut fallback_iterator = fallbacker
        .for_config(config)
        .fallback_for(resource.0.clone().into());

    while !fallback_iterator.get().is_unknown() {
        let data_locale = fallback_iterator.get().clone();
        let locale_string = data_locale.to_string();
        if let Some(input) = available_norm.get(&locale_string) {
            return Ok((atoms::ok(), input).encode(env));
        }
        fallback_iterator.step();
    }

    Ok((atoms::error(), atoms::no_match()).encode(env))
}
