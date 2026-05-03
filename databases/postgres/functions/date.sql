
--Date Manipulation in MySQL

NOW()
CURRENT_DATE()
DATE(NOW()) 
--MICROSECOND, SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, QUARTER, YEAR
Extract(DAY FROM NOW())
Extract(YEAR FROM NOW())
Extract(MONTH FROM NOW())

EXTRACT(MONTH FROM created_at - INTERVAL '1' MONTH)

-- Text to Date
to_date(cast(act_date as text), 'YYYY-MM') as curr_month_year

-- Next Month Date
date(to_date(cast(act_date as text), 'YYYY-MM') + INTERVAL '1 month') as next_month_year


date + integer -> Date
date - date → integer
date + interval → timestamp

--format : datetime formats list


