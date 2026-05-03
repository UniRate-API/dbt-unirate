{#
    unirate.get_historical_rate(from_currency, to_currency, date_column,
                                [rates_relation])
    --------------------------------------------------------------------
    Returns a SQL scalar subquery that resolves to the rate for a given
    (from, to, date), looked up from the materialised
    `unirate__historical_rates` table.

    `date_column` is a SQL expression in the **outer** query — usually a
    column reference like `o.order_date`. The subquery picks the latest
    available rate on or before that date (so weekends / holidays fall
    back to the previous business day's snapshot).

    Example:

        select
          o.amount * {{ unirate.get_historical_rate(
                          'USD', 'EUR', 'o.order_date') }} as amount_eur
        from {{ ref('orders') }} o

    `unirate__historical_rates` is Pro-gated; enable with
    `vars: { unirate_pro_enabled: true }`.
#}
{% macro get_historical_rate(from_currency, to_currency, date_column,
                              rates_relation=None) %}
    {%- set rates = rates_relation if rates_relation is not none else ref('unirate__historical_rates') -%}
    (
        select rate
        from {{ rates }}
        where base_currency = '{{ from_currency | upper }}'
          and target_currency = '{{ to_currency | upper }}'
          and as_of_date <= {{ date_column }}
        order by as_of_date desc
        limit 1
    )
{% endmacro %}
