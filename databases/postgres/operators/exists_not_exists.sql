/*
The EXISTS condition in SQL is used to check whether the result of a CORELATED NESTED QUERY is empty (contains no tuples) or not. 
The result of EXISTS is a boolean value True or False. 
It can be used in a SELECT, UPDATE, INSERT or DELETE statement.
*/

--Find the detail of employee who is working on atleast one project
select * from employee
where eid EXISTS (SELECT eid from project where employee.eid = project.eid)

select * from employee
where eid NOT EXISTS (SELECT eid from project where employee.eid = project.eid)