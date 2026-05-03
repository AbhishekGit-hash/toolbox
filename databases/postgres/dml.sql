/*
To change the actual data that lives in tables, use INSERT, DELETE, and UPDATE statements
To access the data in databse object, use SELECT statements
*/

select

    payment_method,
    sum(amount) AS amount

from {{ ref('raw_payments') }}
group by 1

INSERT INTO raw_customers VALUES (101, 'Kira', 'F.');

DELETE FROM customers WHERE first_name = 'Henry' AND last_name = 'W.';

UPDATE orders SET status = 'returned' WHERE order_id = 7;

