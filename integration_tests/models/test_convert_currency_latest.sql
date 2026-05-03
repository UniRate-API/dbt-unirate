-- Exercises unirate.convert_currency without a date column.
-- order_id=1, amount=100 USD -> 100 * 0.92 (latest USD/EUR) = 92.
select
    order_id,
    amount,
    {{ unirate.convert_currency(
        'amount', 'USD', 'EUR',
        rates_relation=ref('mock_latest_rates')) }} as amount_eur
from {{ ref('orders') }}
