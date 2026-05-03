
CREATE TABLE Emp(
    EmpID INT NOT NULL PRIMARY KEY,
    Name VARCHAR (50),
    Country VARCHAR(50),
    Age int(2),
  Salary int(10));

ALTER TABLE Emp modify Name Varchar(50) NOT NULL;
