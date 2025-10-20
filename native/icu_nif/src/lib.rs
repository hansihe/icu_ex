mod datetime;
mod display_names;
mod list;
mod locale;
mod number;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        invalid_locale,
        invalid_resource,
        invalid_formatter,
        invalid_number,
        invalid_options,
        invalid_datetime,
        invalid_items,
        minimum_integer_digits,
        minimum_fraction_digits,
        maximum_fraction_digits,
        grouping,
        notation,
        sign_display,
        and,
        or,
        unit,
        locale,
        language,
        region,
        script,
        variant,
        auto,
        always,
        min2,
        never,
        standard,
        short,
        wide,
        narrow,
        medium,
        long,
        full,
        menu,
        integer,
        decimal,
        fraction,
        group,
        plus_sign,
        minus_sign,
        except_zero,
        negative,
        code,
        none,
        dialect,
        element,
        date_length,
        time_length,
        hour_cycle,
        h11,
        h12,
        h23,
        h24,
        year,
        month,
        day,
        hour,
        minute,
        second,
        literal,
        day_period,
        time_zone_name,
        weekday,
        era,
        related_year,
        year_name,
        microsecond,
        nanosecond,
        calendar,
        time_zone,
        zone_abbr,
        utc_offset,
        std_offset,
        length,
        date_fields,
        time_precision,
        zone_style,
        alignment,
        year_style,
        calendar_identifier,
        modified,
        unmodified,
        no_match
    }
}

use rustler::{Env, Term};

fn load(env: Env, _term: Term) -> bool {
    locale::load(env)
        && number::load(env)
        && datetime::load(env)
        && list::load(env)
        && display_names::load(env)
}

rustler::init!("Elixir.Icu.Nif", load = load);
