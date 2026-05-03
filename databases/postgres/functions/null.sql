
--ISNULL()
SELECT column(s), ISNULL(column_name, value_to_replace) FROM table_name;

--IFNULL()
SELECT column(s), IFNULL(column_name, value_to_replace) FROM table_name;

--COALESCE function in SQL returns the first non-NULL expression among its arguments. 
--If all the expressions evaluate to null, then the COALESCE function will return null. 
SELECT column(s), COALESCE(expression_1,….,expression_n) FROM table_name;

--NULLIF function takes two arguments. 
--If the two arguments are equal, then NULL is returned. Otherwise, the first argument is returned. 
SELECT Store, NULLIF(Actual, Goal) FROM Sales;
