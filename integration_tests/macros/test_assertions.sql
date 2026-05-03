{# Project-local custom data tests that compare each row against a hand-checked expected value. #}

{% test dbt_utils_equal_value(model, column_name, expected_value, tolerance=0) %}
    select *
    from {{ model }}
    where abs({{ column_name }} - {{ expected_value }}) > {{ tolerance }}
{% endtest %}

{% test row_amount_eur_matches(model, expected_rate) %}
    -- Latest-rate test: every row's amount_eur should equal amount * expected_rate.
    select *
    from {{ model }}
    where abs(amount_eur - amount * {{ expected_rate }}) > 0.0001
{% endtest %}

{% test historical_amount_eur_matches(model) %}
    -- Hand-checked expected values per order_id (see seed comments).
    select *
    from {{ model }}
    where (order_id = 1 and abs(amount_eur - 100 * 0.95) > 0.0001)
       or (order_id = 2 and abs(amount_eur - 200 * 0.93) > 0.0001)
       or (order_id = 3 and abs(amount_eur - 300 * 0.88) > 0.0001)
{% endtest %}

{% test passthrough_amount_unchanged(model) %}
    select *
    from {{ model }}
    where amount_usd <> amount
{% endtest %}
