
CREATE TABLE pets(
        ID INT NOT NULL,
        Name VARCHAR(30) NOT NULL,
        Breed VARCHAR(20) NOT NULL,
        Age INT,
        GENDER VARCHAR(9),
        PRIMARY KEY(ID),
        check(GENDER in ('Male', 'Female', 'Unknown'))
        );

alter table TABLE_NAME modify COLUMN_NAME check(Predicate);

alter table TABLE_NAME add constraint CHECK_CONST check (Predicate);

--SQL server
alter table TABLE_NAME drop constraint CHECK_CONSTRAINT_NAME;

--MySQL
alter table TABLE_NAME drop check CHECK_CONSTRAINT_NAME;

--Viewing Tables and Constraints
SELECT * 
FROM information_schema.table_constraints 
WHERE table_schema = schema() 
AND table_name = 'employee';
