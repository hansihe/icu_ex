use std::fmt;

use icu::list::options::{ListFormatterOptions, ListLength};
use icu::list::{parts, ListFormatter};
use rustler::types::map::MapIterator;
use rustler::{Atom, Encoder, Env, NifMap, NifResult, ResourceArc, Term, TermType};
use writeable::{Part as WriteablePart, PartsWrite, Writeable};

use crate::atoms;
use crate::locale::LocaleResource;

pub(crate) struct ListFormatterResource {
    formatter: ListFormatter,
}

impl rustler::Resource for ListFormatterResource {}

#[derive(Copy, Clone)]
enum ListType {
    And,
    Or,
    Unit,
}

#[derive(Copy, Clone)]
struct FormatterConfig {
    list_type: ListType,
    length: ListLength,
}

impl Default for FormatterConfig {
    fn default() -> Self {
        Self {
            list_type: ListType::And,
            length: ListLength::Wide,
        }
    }
}

#[derive(NifMap)]
struct ListFormatPart {
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

    fn into_parts(self) -> (String, Vec<CollectedPart>) {
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
    env.register::<ListFormatterResource>().is_ok()
}

#[rustler::nif]
pub(crate) fn list_formatter_new<'a>(
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

    let options = ListFormatterOptions::default().with_length(config.length);

    let formatter = match config.list_type {
        ListType::And => ListFormatter::try_new_and(locale_resource.0.clone().into(), options),
        ListType::Or => ListFormatter::try_new_or(locale_resource.0.clone().into(), options),
        ListType::Unit => ListFormatter::try_new_unit(locale_resource.0.clone().into(), options),
    };

    let formatter = match formatter {
        Ok(formatter) => formatter,
        Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
    };

    let resource = ListFormatterResource { formatter };

    Ok((atoms::ok(), ResourceArc::new(resource)).encode(env))
}

#[rustler::nif]
pub(crate) fn list_format<'a>(
    env: Env<'a>,
    formatter_term: Term<'a>,
    items_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let formatter_resource: ResourceArc<ListFormatterResource> = match formatter_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_formatter()).encode(env)),
    };

    let items: Vec<String> = match items_term.decode() {
        Ok(items) => items,
        Err(_) => return Ok((atoms::error(), atoms::invalid_items()).encode(env)),
    };

    if items.is_empty() {
        return Ok((atoms::error(), atoms::invalid_items()).encode(env));
    }

    let iter = items.iter().map(|value| value.as_str());
    let formatted = formatter_resource.formatter.format(iter);
    let output = formatted.write_to_string().into_owned();

    Ok((atoms::ok(), output).encode(env))
}

#[rustler::nif]
pub(crate) fn list_format_to_parts<'a>(
    env: Env<'a>,
    formatter_term: Term<'a>,
    items_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let formatter_resource: ResourceArc<ListFormatterResource> = match formatter_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_formatter()).encode(env)),
    };

    let items: Vec<String> = match items_term.decode() {
        Ok(items) => items,
        Err(_) => return Ok((atoms::error(), atoms::invalid_items()).encode(env)),
    };

    if items.is_empty() {
        return Ok((atoms::error(), atoms::invalid_items()).encode(env));
    }

    let iter = items.iter().map(|value| value.as_str());
    let formatted = formatter_resource.formatter.format(iter);

    let mut collector = PartsCollector::new();
    if formatted.write_to_parts(&mut collector).is_err() {
        return Ok((atoms::error(), atoms::invalid_items()).encode(env));
    }

    let (output, collected_parts) = collector.into_parts();
    let mut parts = Vec::with_capacity(collected_parts.len());

    for collected in collected_parts {
        if let Some(atom) = part_atom(collected.part) {
            if let Some(slice) = output.get(collected.start..collected.end) {
                parts.push(ListFormatPart {
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
        let key = key_term.atom_to_string().map_err(|_| ())?;

        if key == "type" {
            let value: Atom = value_term.decode().map_err(|_| ())?;
            config.list_type = if value == atoms::and() {
                ListType::And
            } else if value == atoms::or() {
                ListType::Or
            } else if value == atoms::unit() {
                ListType::Unit
            } else {
                return Err(());
            };
        } else if key == "width" {
            let value: Atom = value_term.decode().map_err(|_| ())?;
            config.length = if value == atoms::wide() {
                ListLength::Wide
            } else if value == atoms::short() {
                ListLength::Short
            } else if value == atoms::narrow() {
                ListLength::Narrow
            } else {
                return Err(());
            };
        } else if key == "locale" {
            // Locale is handled on the Elixir side and should not be forwarded to the NIF.
            continue;
        } else {
            // Ignore unknown keys so long as they are nil.
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

    Ok(config)
}

fn part_atom(part: WriteablePart) -> Option<Atom> {
    if part == parts::ELEMENT {
        Some(atoms::element())
    } else if part == parts::LITERAL {
        Some(atoms::literal())
    } else {
        None
    }
}
