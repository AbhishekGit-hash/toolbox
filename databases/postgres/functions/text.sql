
--String Functions
CHARACTER_LENGTH(), LEN()
LENGTH('GeeksForGeeks')
SELECT 'Geeks' || ' ' || 'forGeeks' FROM dual;
Format("0.981", "Percent")

LOWER('GEEKSFORGEEKS.ORG')
UPPER ("GeeksForGeeks")

LEFT('geeksforgeeks.org', 5)
RIGHT('geeksforgeeks.org', 4)

LPAD('geeks', 8, '0')
RPAD('geeks', 8, '0')

LTRIM('123123geeks', '123')
TRIM(LEADING '0' FROM '000123')

REPLACE('123geeks123', '123')
REVERSE('geeksforgeeks.org')

STRCMP('google.com', 'geeksforgeeks.com')
SUBSTRING('GeeksForGeeks.org', 9, 1)



