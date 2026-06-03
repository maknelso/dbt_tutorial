select 
    order_id,
    sum(payment_amount) as total_amount
from
    {{ ref('stg_stripe__payments') }}
group by 1
-- cannot have semicolon for tests
-- having filter is before SELECT clause, so we have to use sum(payment_amount)
having sum(payment_amount) < 0 