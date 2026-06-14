{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='customer_id',
        on_schema_change='fail'
    )
}}

with customers as (
    select * from {{ ref('stg_jaffle_shop__customers') }}
),

orders as (
    select * from {{ ref('stg_jaffle_shop__orders') }}
    -- if this table already eixst, only pull data that has arrived since last time we ran this model
    {% if is_incremental() %}
        -- Fixes Snowflake correlation error and targets the correct column name
        where order_date >= (
            select max_date from (
                select max(most_recent_order_date) as max_date from {{ this }}
            )
        )
    {% endif %}
),

payments as (
    select * from {{ ref('stg_stripe__payments') }}
),

customer_orders as (
    select
        orders.customer_id,
        min(orders.order_date) as first_order_date,
        max(orders.order_date) as most_recent_order_date,
        count(orders.order_id) as number_of_orders,
        sum(payments.payment_amount) as lifetime_value
    from orders
    left join payments using (order_id)
    group by 1
),

final as (
    select
        customers.customer_id as customer_idd,
        customers.first_name,
        customers.last_name,
        customer_orders.first_order_date,
        customer_orders.most_recent_order_date,
        coalesce(customer_orders.number_of_orders, 0) as number_of_orders,
        coalesce(customer_orders.lifetime_value, 0) as lifetime_value
    from customers
    left join customer_orders using (customer_id)
)

select * from final