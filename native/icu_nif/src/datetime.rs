use std::fmt;

use icu::calendar::{AnyCalendar, Date};
use icu::datetime::fieldsets::builder::FieldSetBuilder;
use icu::datetime::fieldsets::enums::CompositeFieldSet;
use icu::datetime::input::Time;
use icu::datetime::options;
use icu::datetime::unchecked::DateTimeInputUnchecked;
use icu::datetime::{parts as datetime_parts, DateTimeFormatter, DateTimeFormatterPreferences};
use icu::decimal::parts as decimal_parts;
use icu::time::zone::{IanaParser, UtcOffset};
use rustler::types::map::MapIterator;
use rustler::{Atom, Encoder, Env, NifMap, NifResult, NifTaggedEnum, ResourceArc, Term, TermType};
use writeable::{Part as WriteablePart, PartsWrite, TryWriteable};

use crate::atoms;
use crate::locale::LocaleResource;

pub(crate) struct DateTimeFormatterResource(DateTimeFormatter<CompositeFieldSet>);

impl rustler::Resource for DateTimeFormatterResource {}

#[derive(NifMap)]
struct DateTimeFormatPart {
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

    fn finish(self) -> (String, Vec<CollectedPart>) {
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
    env.register::<DateTimeFormatterResource>().is_ok()
}

#[rustler::nif]
pub(crate) fn temporal_formatter_new<'a>(
    env: Env<'a>,
    locale_term: Term<'a>,
    options_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let locale_resource: ResourceArc<LocaleResource> = match locale_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
    };

    let field_set = match build_field_set(options_term) {
        Ok(field_set) => field_set,
        Err(_error) => return Ok((atoms::error(), atoms::invalid_options()).encode(env)),
    };

    let prefs: DateTimeFormatterPreferences = locale_resource.0.clone().into();

    let formatter = match DateTimeFormatter::try_new(prefs, field_set) {
        Ok(formatter) => formatter,
        Err(_) => return Ok((atoms::error(), atoms::invalid_locale()).encode(env)),
    };

    let resource = ResourceArc::new(DateTimeFormatterResource(formatter));
    Ok((atoms::ok(), resource).encode(env))
}

#[rustler::nif]
pub(crate) fn temporal_format<'a>(
    env: Env<'a>,
    formatter_term: Term<'a>,
    datetime_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let formatter_resource: ResourceArc<DateTimeFormatterResource> = match formatter_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_formatter()).encode(env)),
    };

    let formatter_calendar = formatter_resource.0.calendar();

    let input = match decode_temporal(datetime_term, formatter_calendar.0) {
        Ok(datetime) => datetime,
        Err(_) => return Ok((atoms::error(), atoms::invalid_datetime()).encode(env)),
    };

    let formatted_unchecked = formatter_resource.0.format_unchecked(input);
    let formatted_result = formatted_unchecked.try_write_to_string();

    match formatted_result {
        Ok(str) => Ok((atoms::ok(), &*str).encode(env)),
        Err(_) => todo!(),
    }
}

#[rustler::nif]
pub(crate) fn temporal_format_to_parts<'a>(
    env: Env<'a>,
    formatter_term: Term<'a>,
    datetime_term: Term<'a>,
) -> NifResult<Term<'a>> {
    let formatter_resource: ResourceArc<DateTimeFormatterResource> = match formatter_term.decode() {
        Ok(resource) => resource,
        Err(_) => return Ok((atoms::error(), atoms::invalid_formatter()).encode(env)),
    };

    let formatter_calendar = formatter_resource.0.calendar();

    let input = match decode_temporal(datetime_term, formatter_calendar.0) {
        Ok(datetime) => datetime,
        Err(_) => return Ok((atoms::error(), atoms::invalid_datetime()).encode(env)),
    };

    let formatted = formatter_resource.0.format_unchecked(input);

    let mut collector = PartsCollector::new();
    if let Err(_) = formatted.try_write_to_parts(&mut collector) {
        return Ok((atoms::error(), atoms::invalid_datetime()).encode(env));
    }
    let (output, collected_parts) = collector.finish();

    let mut parts = Vec::new();
    let mut last_index = 0usize;

    for collected in collected_parts {
        if collected.start > last_index {
            if let Some(slice) = output.get(last_index..collected.start) {
                if !slice.is_empty() {
                    parts.push(DateTimeFormatPart {
                        part_type: atoms::literal(),
                        value: slice.to_string(),
                    });
                }
            }
        }

        if let Some(atom) = part_atom(collected.part) {
            if let Some(slice) = output.get(collected.start..collected.end) {
                parts.push(DateTimeFormatPart {
                    part_type: atom,
                    value: slice.to_string(),
                });
            }
        }

        last_index = collected.end;
    }

    if last_index < output.len() {
        if let Some(slice) = output.get(last_index..output.len()) {
            if !slice.is_empty() {
                parts.push(DateTimeFormatPart {
                    part_type: atoms::literal(),
                    value: slice.to_string(),
                });
            }
        }
    }

    Ok((atoms::ok(), parts).encode(env))
}

fn decode_temporal<'a>(
    term: Term<'a>,
    _ref_calendar: &AnyCalendar,
) -> Result<DateTimeInputUnchecked, ()> {
    if term.get_type() != TermType::Map {
        return Err(());
    }

    let mut unchecked = DateTimeInputUnchecked::default();

    let mut iter = MapIterator::new(term).ok_or(())?;
    let mut year: Option<i32> = None;
    let mut month: Option<u8> = None;
    let mut day: Option<u8> = None;
    let mut hour: Option<u8> = None;
    let mut minute: Option<u8> = None;
    let mut second: Option<u8> = None;
    let mut microsecond: Option<(u32, u32)> = None;

    while let Some((key_term, value_term)) = iter.next() {
        let key: Atom = key_term.decode().map_err(|_| ())?;
        if key == atoms::year() {
            year = Some(value_term.decode().map_err(|_| ())?);
        } else if key == atoms::month() {
            let value: i64 = value_term.decode().map_err(|_| ())?;
            if !(1..=12).contains(&value) {
                return Err(());
            }
            month = Some(value as u8);
        } else if key == atoms::day() {
            let value: i64 = value_term.decode().map_err(|_| ())?;
            if !(1..=31).contains(&value) {
                return Err(());
            }
            day = Some(value as u8);
        } else if key == atoms::hour() {
            let value: i64 = value_term.decode().map_err(|_| ())?;
            if !(0..=23).contains(&value) {
                return Err(());
            }
            hour = Some(value as u8);
        } else if key == atoms::minute() {
            let value: i64 = value_term.decode().map_err(|_| ())?;
            if !(0..=59).contains(&value) {
                return Err(());
            }
            minute = Some(value as u8);
        } else if key == atoms::second() {
            let value: i64 = value_term.decode().map_err(|_| ())?;
            if !(0..=59).contains(&value) {
                return Err(());
            }
            second = Some(value as u8);
        } else if key == atoms::microsecond() {
            let (ms, us): (u32, u32) = value_term.decode().map_err(|_| ())?;
            if !(0..=999_999).contains(&ms) {
                return Err(());
            }
            if !(0..=6).contains(&us) {
                return Err(());
            }
            microsecond = Some((ms, us));
        } else if key == atoms::time_zone() {
            let str = value_term.decode::<&str>().map_err(|_| ())?;
            unchecked.set_time_zone_id(IanaParser::new().parse(str));
        } else if key == atoms::utc_offset() {
            let seconds: i32 = value_term.decode::<i32>().map_err(|_| ())?;
            let offset = UtcOffset::try_from_seconds(seconds).map_err(|_| ())?;
            unchecked.set_time_zone_utc_offset(offset);
        } else if key == atoms::calendar_identifier() {
            // calendar: Calendar.calendar()
            // TODO
        }
    }

    if year.is_some() || month.is_some() || day.is_some() {
        let date =
            Date::try_new_iso(year.ok_or(())?, month.ok_or(())?, day.ok_or(())?).map_err(|_| ())?;
        unchecked.set_date_fields_unchecked(date);
    }

    if hour.is_some() || minute.is_some() || second.is_some() || microsecond.is_some() {
        let (us, _precision) = microsecond.ok_or(())?;
        let time = Time::try_new(
            hour.ok_or(())?,
            minute.ok_or(())?,
            second.ok_or(())?,
            us * 1_000,
        )
        .map_err(|_| ())?;
        unchecked.set_time_fields(time);
    }

    Ok(unchecked)
}

#[derive(NifTaggedEnum)]
enum TemporalLength {
    Long,
    Medium,
    Short,
}

#[derive(NifTaggedEnum)]
enum TemporalDateFields {
    D,
    MD,
    YMD,
    DE,
    MDE,
    YMDE,
    E,
    M,
    YM,
    Y,
}

#[derive(NifTaggedEnum)]
enum TemporalTimePrecision {
    Hour,
    Minute,
    Second,
    Subsecond(u8),
    MinuteOptional,
}

#[derive(NifTaggedEnum)]
pub enum TemporalZoneStyle {
    SpecificLong,
    SpecificShort,
    LocalizedOffsetLong,
    LocalizedOffsetShort,
    GenericLong,
    GenericShort,
    Location,
    ExemplarCity,
}

#[derive(NifTaggedEnum)]
pub enum TemporalAlignment {
    Auto,
    Column,
}

#[derive(NifTaggedEnum)]
pub enum YearStyle {
    Auto,
    Full,
    WithEra,
}

fn build_field_set(term: Term) -> Result<CompositeFieldSet, ()> {
    let mut options_iter = MapIterator::new(term).ok_or(())?;

    let mut builder = FieldSetBuilder::new();

    while let Some((key_term, value_term)) = options_iter.next() {
        let key: Atom = key_term.decode().map_err(|_| ())?;

        if key == atoms::length() {
            let len_term: TemporalLength = value_term.decode().map_err(|_| ())?;
            use options::Length;
            builder.length = Some(match len_term {
                TemporalLength::Long => Length::Long,
                TemporalLength::Medium => Length::Medium,
                TemporalLength::Short => Length::Short,
            });
        } else if key == atoms::date_fields() {
            let date_fields: TemporalDateFields = value_term.decode().map_err(|_| ())?;
            use icu::datetime::fieldsets::builder::DateFields;
            builder.date_fields = Some(match date_fields {
                TemporalDateFields::D => DateFields::D,
                TemporalDateFields::MD => DateFields::MD,
                TemporalDateFields::YMD => DateFields::YMD,
                TemporalDateFields::DE => DateFields::DE,
                TemporalDateFields::MDE => DateFields::MDE,
                TemporalDateFields::YMDE => DateFields::YMDE,
                TemporalDateFields::E => DateFields::E,
                TemporalDateFields::M => DateFields::M,
                TemporalDateFields::YM => DateFields::YM,
                TemporalDateFields::Y => DateFields::Y,
            });
        } else if key == atoms::time_precision() {
            let precision: TemporalTimePrecision = value_term.decode().map_err(|_| ())?;
            use options::{SubsecondDigits, TimePrecision};
            builder.time_precision = Some(match precision {
                TemporalTimePrecision::Hour => TimePrecision::Hour,
                TemporalTimePrecision::Minute => TimePrecision::Minute,
                TemporalTimePrecision::Second => TimePrecision::Second,
                TemporalTimePrecision::Subsecond(1) => {
                    TimePrecision::Subsecond(SubsecondDigits::S1)
                }
                TemporalTimePrecision::Subsecond(2) => {
                    TimePrecision::Subsecond(SubsecondDigits::S2)
                }
                TemporalTimePrecision::Subsecond(3) => {
                    TimePrecision::Subsecond(SubsecondDigits::S3)
                }
                TemporalTimePrecision::Subsecond(4) => {
                    TimePrecision::Subsecond(SubsecondDigits::S4)
                }
                TemporalTimePrecision::Subsecond(5) => {
                    TimePrecision::Subsecond(SubsecondDigits::S5)
                }
                TemporalTimePrecision::Subsecond(6) => {
                    TimePrecision::Subsecond(SubsecondDigits::S6)
                }
                TemporalTimePrecision::Subsecond(7) => {
                    TimePrecision::Subsecond(SubsecondDigits::S7)
                }
                TemporalTimePrecision::Subsecond(8) => {
                    TimePrecision::Subsecond(SubsecondDigits::S8)
                }
                TemporalTimePrecision::Subsecond(9) => {
                    TimePrecision::Subsecond(SubsecondDigits::S9)
                }
                TemporalTimePrecision::Subsecond(_) => return Err(()),
                TemporalTimePrecision::MinuteOptional => TimePrecision::MinuteOptional,
            });
        } else if key == atoms::zone_style() {
            let style: TemporalZoneStyle = value_term.decode().map_err(|_| ())?;
            use icu::datetime::fieldsets::builder::ZoneStyle;
            builder.zone_style = Some(match style {
                TemporalZoneStyle::SpecificLong => ZoneStyle::SpecificLong,
                TemporalZoneStyle::SpecificShort => ZoneStyle::SpecificShort,
                TemporalZoneStyle::LocalizedOffsetLong => ZoneStyle::LocalizedOffsetLong,
                TemporalZoneStyle::LocalizedOffsetShort => ZoneStyle::LocalizedOffsetShort,
                TemporalZoneStyle::GenericLong => ZoneStyle::GenericLong,
                TemporalZoneStyle::GenericShort => ZoneStyle::GenericShort,
                TemporalZoneStyle::Location => ZoneStyle::Location,
                TemporalZoneStyle::ExemplarCity => ZoneStyle::ExemplarCity,
            });
        } else if key == atoms::alignment() {
            let alignment: TemporalAlignment = value_term.decode().map_err(|_| ())?;
            builder.alignment = Some(match alignment {
                TemporalAlignment::Auto => options::Alignment::Auto,
                TemporalAlignment::Column => options::Alignment::Column,
            });
        } else if key == atoms::year_style() {
            let style: YearStyle = value_term.decode().map_err(|_| ())?;
            builder.year_style = Some(match style {
                YearStyle::Auto => options::YearStyle::Auto,
                YearStyle::Full => options::YearStyle::Full,
                YearStyle::WithEra => options::YearStyle::WithEra,
            });
        }
    }

    builder.build_composite().map_err(|_| ())
}

fn part_atom(part: WriteablePart) -> Option<Atom> {
    if part == datetime_parts::ERA {
        Some(atoms::era())
    } else if part == datetime_parts::YEAR {
        Some(atoms::year())
    } else if part == datetime_parts::RELATED_YEAR {
        Some(atoms::related_year())
    } else if part == datetime_parts::YEAR_NAME {
        Some(atoms::year_name())
    } else if part == datetime_parts::MONTH {
        Some(atoms::month())
    } else if part == datetime_parts::DAY {
        Some(atoms::day())
    } else if part == datetime_parts::WEEKDAY {
        Some(atoms::weekday())
    } else if part == datetime_parts::DAY_PERIOD {
        Some(atoms::day_period())
    } else if part == datetime_parts::HOUR {
        Some(atoms::hour())
    } else if part == datetime_parts::MINUTE {
        Some(atoms::minute())
    } else if part == datetime_parts::SECOND {
        Some(atoms::second())
    } else if part == datetime_parts::TIME_ZONE_NAME {
        Some(atoms::time_zone_name())
    } else if part == decimal_parts::INTEGER {
        Some(atoms::integer())
    } else if part == decimal_parts::DECIMAL {
        Some(atoms::decimal())
    } else if part == decimal_parts::FRACTION {
        Some(atoms::fraction())
    } else {
        None
    }
}
