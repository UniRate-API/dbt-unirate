-- Same currency -> passthrough, no rate lookup, no joined relation.
-- Should return `amount` verbatim for all rows.
select
    order_id,
    amount,
    {{ unirate.convert_currency('amount', 'USD', 'USD') }} as amount_usd
from {{ ref('orders') }}
