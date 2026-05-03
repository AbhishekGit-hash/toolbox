/*

Three types of analytic functions
The example above uses only one of many analytic functions. 

1) Analytic aggregate functions

Aggregate functions take all of the values within the window as input and return a single value.
AVG()
MIN() (or MAX()) - Returns the minimum (or maximum) of input values
AVG() (or SUM()) - Returns the average (or sum) of input values
COUNT() - Returns the number of rows in the input

2) Analytic navigation functions
Navigation functions assign a value based on the value in a (usually) different row than the current row.

FIRST_VALUE() (or LAST_VALUE()) - Returns the first (or last) value in the input
LEAD() (and LAG()) - Returns the value on a subsequent (or preceding) row

3) Analytic numbering functions
Numbering functions assign integer values to each row based on the ordering.

ROW_NUMBER() - Returns the order in which rows appear in the input (starting with 1)
RANK() - All rows with the same value in the ordering column receive the same rank value, 
where the next row receives a rank value which increments by the number of rows with the previous rank value.


WINDOW FRAME CLAUSE :
ROWS BETWEEN 1 PRECEDING AND CURRENT ROW - the previous row and the current row.
ROWS BETWEEN 3 PRECEDING AND 1 FOLLOWING - the 3 previous rows, the current row, and the following row.
ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING - all rows in the partition.

*/

SELECT bike_number,
        TIME(start_date) AS trip_time,
        FIRST_VALUE(start_station_id)
            OVER (
                PARTITION BY bike_number
                ORDER BY start_date
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                ) AS first_station_id,
        LAST_VALUE(end_station_id)
            OVER (
                PARTITION BY bike_number
                ORDER BY start_date
                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                ) AS last_station_id,
        start_station_id,
        end_station_id
FROM `bigquery-public-data.san_francisco.bikeshare_trips`
WHERE DATE(start_date) = '2015-10-25' 