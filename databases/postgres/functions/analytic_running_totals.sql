
--Running Sum
select *,
sum(cost) over (order by cost asc 
                rows between UNBOUNDED preceding and current row --running sun
                ) as running_cost
from products;

--Rolling Sum, Avg, Max, Min 3 months

with year_month_sales as (
    select datepart(year, order_date) as year_order,
            datepart(month, order_date) as month_order,
            sum(sales) as sales
    from cust_orders
    group by datepart(year, order_date),
            datepart(month, order_date)
)

select *,
sum(sales) over(order by year_order asc, month_order asc 
                rows between 2 preceding and current row --rolling 3M
                ) as rolling_3_months_sum
from year_month_sales;

-- 7 Day Moving Average

SELECT *,
      avg(confirmed_day) OVER(
          PARTITION BY country
          ORDER BY date
          ROWS BETWEEN 6 PRECEDING AND CURRENT ROW --Moving/Rolling 7Day
          )
          AS 7day_moving_average
FROM confirmed_covid;
