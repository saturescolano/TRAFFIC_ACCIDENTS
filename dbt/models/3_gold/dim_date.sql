with dates as (
    select start_time_local::date as full_date from {{ ref('accident') }}
    union
    select end_time_local::date from {{ ref('accident') }}
)
select
    to_number(to_char(full_date, 'YYYYMMDD'))   as date_key,
    full_date,
    day(full_date)::smallint                    as day,
    month(full_date)::smallint                  as month,
    quarter(full_date)::smallint                as quarter,
    year(full_date)::smallint                   as year,
    dayofweekiso(full_date)::smallint           as weekday,
    dayofweekiso(full_date) >= 6                as weekend_flag
from dates
where full_date is not null
