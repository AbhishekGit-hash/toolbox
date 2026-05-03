/*
SELECT (ColumnNames) 
FROM (TableName) 
PIVOT
 ( 
   AggregateFunction(ColumnToBeAggregated)
   FOR PivotColumn IN (PivotColumnValues)
 ) AS (Alias) //Alias is a temporary name for a table

 SELECT (ColumnNames) 
FROM (TableName) 
UNPIVOT
 ( 
   AggregateFunction(ColumnToBeAggregated)
   FOR PivotColumn IN (PivotColumnValues)
 ) AS (Alias)

 Sample table columns : CourseName	CourseCategory	Price
 */

SELECT CourseName, PROGRAMMING, INTERVIEWPREPARATION
FROM geeksforgeeks 
PIVOT 
( 
SUM(Price) FOR CourseCategory IN (PROGRAMMING, INTERVIEWPREPARATION ) 
) AS PivotTable

--UNPIVOT

SELECT CourseName, CourseCategory, Price 
FROM 
(
    SELECT CourseName, PROGRAMMING, INTERVIEWPREPARATION FROM geeksforgeeks 
    PIVOT 
    ( 
    SUM(Price) FOR CourseCategory IN (PROGRAMMING, INTERVIEWPREPARATION) 
    ) AS PivotTable
) P 
UNPIVOT 
( 
Price FOR CourseCategory IN (PROGRAMMING, INTERVIEWPREPARATION)
) 
AS UnpivotTable


