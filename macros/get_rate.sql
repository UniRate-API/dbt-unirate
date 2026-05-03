{#
    unirate.get_rate(from_currency, to_currency, [rates_relation])
    -----------------------------------------------------------
    Returns a SQL scalar subquery that resolves to the most recent rate
    that converts `from_currency` -> `to_currency` from the materialised
    `unirate__exchange_rates` table.

    Both currency codes are upper-cased before lookup.

    Use it inline anywhere a numeric expression is valid:

        select
          amount * {{ unirate.get_rate('USD', 'EUR') }} as amount_eur
        from {{ ref('orders') }}

    Override the rates source if you store them elsewhere:

        {{ unirate.get_rate('USD', 'EUR',
                            rates_relation=ref('my_custom_rates')) }}

    The rates table must expose the columns
    `as_of_date`, `base_currency`, `target_currency`, `rate`.
#}
{% macro get_rate(from_currency, to_currency, rates_relation=None) %}
    {%- set rates = rates_relation if rates_relation is not none else ref('unirate__exchange_rates') -%}
    (
        select rate
        from {{ rates }}
        where base_currency = '{{ from_currency | upper }}'
          and target_currency = '{{ to_currency | upper }}'
        order by as_of_date desc
        limit 1
    )
{% endmacro %}
