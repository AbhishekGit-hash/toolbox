Create Table Person
(
Id int NOT NULL PRIMARY KEY, 
Name varchar2(20), 
Address varchar2(50)
);

Alter Table Person add Primary Key(Id, Name);

ALTER table Person DROP PRIMARY KEY;

