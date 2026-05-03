/*
The ALL operator returns TRUE if all of the subqueries values meet the condition. 
The ANY / SOME operator returns TRUE if all of the subqueries values meet the condition. 

The ALL must be preceded by comparison operators and evaluates true if all of the subqueries values meet the condition.
ALL is used with SELECT, WHERE, HAVING statement.
*/

--Find the name of the product if all the records in the OrderDetails has Quantity either equal to 6 or 2.
SELECT ProductName 
FROM Products
WHERE ProductID = ALL (SELECT ProductId
                       FROM OrderDetails
                       WHERE Quantity = 6 OR Quantity = 2);

--Finds any records in the OrderDetails table that Quantity = 9
SELECT ProductName
FROM Products
WHERE ProductID = ANY (SELECT ProductID
                       FROM OrderDetails
                       WHERE Quantity = 9);

