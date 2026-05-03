{#
    unirate.convert_currency(amount, from_currency, to_currency,
                             [date_column], [rates_relation])
    ------------------------------------------------------------
    Returns a SQL expression that converts `amount` (a numeric column
    or scalar) from `from_currency` to `to_currency`.

    Without `date_column`, looks up the most recent rate from
    `ref('unirate__exchange_rates')`.

    With `date_column`, looks up the rate as of that date from
    `ref('unirate__historical_rates')` (Pro-gated; falls back to the
    latest rate on or before the given date).

    Examples:

        -- live rate
        select
          {{ unirate.convert_currency('amount', 'USD', 'EUR') }} as amount_eur
        from {{ ref('orders') }}

        -- historical rate, dated per row
        select
          {{ unirate.convert_currency('amount', 'USD', 'EUR',
                                       date_column='order_date') }} as amount_eur
        from {{ ref('orders') }}

    Pass-through is automatic when `from == to` (the macro just returns
    `amount` so you don't pay for an unnecessary subquery).
#}
{% macro convert_currency(amount, from_currency, to_currency,
                          date_column=None, rates_relation=None) %}
    {%- if (from_currency | upper) == (to_currency | upper) -%}
        ({{ amount }})
    {%- elif date_column is none -%}
        ({{ amount }} * {{ unirate.get_rate(from_currency, to_currency, rates_relation=rates_relation) }})
    {%- else -%}
        ({{ amount }} * {{ unirate.get_historical_rate(from_currency, to_currency, date_column, rates_relation=rates_relation) }})
    {%- endif -%}
{% endmacro %}
