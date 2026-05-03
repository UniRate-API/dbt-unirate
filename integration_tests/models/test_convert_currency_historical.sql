-- Exercises unirate.convert_currency with a date column.
-- Uses mock_historical_rates: 2024-01-01=0.95, 2024-06-01=0.93, 2024-12-01=0.91, 2025-06-01=0.88.
-- 2024-01-15 -> 0.95, 2024-07-15 -> 0.93, 2025-07-15 -> 0.88.
select
    order_id,
    order_date,
    amount,
    {{ unirate.convert_currency(
        'amount', 'USD', 'EUR',
        date_column='order_date',
        rates_relation=ref('mock_historical_rates')) }} as amount_eur
from {{ ref('orders') }}
