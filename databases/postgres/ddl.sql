/*
DDL statements are used to create, drop, and manipulate objects in your database.
ALTER, DROP, CREATE, TRUNCATE
*/

ALTER TABLE customers rename column last_name as last_initial;

DROP TABLE customers;

CREATE TABLE prod.jaffle_shop.jaffles (
    id varchar(255),
    jaffle_name varchar(255)
    created_at timestamp,
    ingredients_list varchar(255),
    is_active boolean
);

/*
he TRUNCATE command will remove all rows from a table while maintaining the underlying table structure. 
The TRUNCATE command is only applicable for table objects in a database. 
Unlike DROP statements, TRUNCATE statements don’t remove the actual table from the database, just the data stored in them.
*/
TRUNCATE TABLE payments;

