with
    -- Import CTEs
    customers as (select * from {{ source("jaffle_shop", "customers") }}),

    orders as (select * from {{ source("jaffle_shop", "orders") }}),

    payments as (select * from {{ source("stripe", "payment") }}),

    -- Logical CTEs
    completed_payments as (
        select
            orderid as order_id,
            max(created) as payment_finalized_date,
            sum(amount) / 100.0 as total_amount_paid
        from payments
        where status <> 'fail'
        group by 1
    ),

    paid_orders as (
        select
            orders.id as order_id,
            orders.user_id as customer_id,
            orders.order_date as order_placed_at,
            orders.status as order_status,
            completed_payments.total_amount_paid,
            completed_payments.payment_finalized_date,
            customers.first_name as customer_first_name,
            customers.last_name as customer_last_name
        from orders
        left join completed_payments on orders.id = completed_payments.order_id
        left join customers on orders.user_id = customers.id
    ),

    customer_lifetime_value as (
        select 
            paid_orders.order_id, 
            sum(t2.total_amount_paid) as clv_bad
        from paid_orders
        left join paid_orders t2
            on paid_orders.customer_id = t2.customer_id
            and paid_orders.order_id >= t2.order_id
        group by 1
    ),

    -- Final CTE (No more customer_orders join!)
    final as (
        select
            paid_orders.*,
            
            -- Window functions for sequencing
            row_number() over (
                order by paid_orders.order_id
            ) as transaction_seq,
            
            row_number() over (
                partition by paid_orders.customer_id 
                order by paid_orders.order_id
            ) as customer_sales_seq,
            
            -- New vs Returning Customer transformation logic (Rule 3 from screenshot)
            case
                when (
                    rank() over (
                        partition by paid_orders.customer_id
                        order by paid_orders.order_placed_at, paid_orders.order_id
                    ) = 1
                ) then 'new'
                else 'return'
            end as nvsr,
            
            -- Customer Lifetime Value reference
            customer_lifetime_value.clv_bad as customer_lifetime_value,
            
            -- First Order Date simplified using first_value window function (Rule 1 & 3 from screenshot)
            first_value(paid_orders.order_placed_at) over (
                partition by paid_orders.customer_id 
                order by paid_orders.order_placed_at
            ) as fdos
            
        from paid_orders
        left outer join customer_lifetime_value 
            on customer_lifetime_value.order_id = paid_orders.order_id
    )

-- Simple Select Statement
select *
from final
order by order_id