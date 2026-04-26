## Defining a Window

```py
from pyspark.sql.window import Window
from pyspark.sql.functions import row_number, rank, dense_rank, lag, lead, sum, avg, count, col

# Window partitioned by department, ordered by salary
dept_window = (
    Window.partitionBy('department')
    .orderBy(col('salary').desc())
)

# Window with frame specification
running_window = (
    Window.partitionBy('department')
    .orderBy('date')
    .rowsBetween(Window.unboundedPreceding, Window.currentRow)
)

# Window without partition (entire DataFrame)
global_window = Window.orderBy(col('salary').desc())
```

## Ranking Functions

```py
# ROW_NUMBER: Unique sequential number (1, 2, 3, 4)
df = df.withColumn('row_num', row_number().over(dept_window))

# RANK: Same rank for ties, gaps after (1, 2, 2, 4)
df = df.withColumn('rank', rank().over(dept_window))

# DENSE_RANK: Same rank for ties, no gaps (1, 2, 2, 3)
df = df.withColumn('dense_rank', dense_rank().over(dept_window))

# Common pattern: Get top N per group
top3_per_dept = (
    df.withColumn('rn', row_number().over(dept_window))
    .filter(col('rn') <= 3)
    .drop('rn')
)
```

## Analytical Functions

```py
window = Window.partitionBy('department').orderBy('date')

# LAG: Access previous row's value
df = df.withColumn('prev_salary', lag('salary', 1).over(window))

# LEAD: Access next row's value
df = df.withColumn('next_salary', lead('salary', 1).over(window))

# Month-over-month change
df = df.withColumn('salary_change', col('salary') - lag('salary', 1).over(window))

# Percentage change
df = df.withColumn('pct_change', ((col('salary') - lag('salary', 1).over(window)) / lag('salary', 1).over(window) * 100))
```

## Running Totals & Moving Averages

```py
# Running total within each department
running = (
    Window.partitionBy('department')
    .orderBy('date')
    .rowsBetween(Window.unboundedPreceding, Window.currentRow)
)
df = df.withColumn('running_total', sum('revenue').over(running))

# 7-day moving average
moving_7d = (
    Window.partitionBy('department')
    .orderBy('date')
    .rowsBetween(-6, Window.currentRow) # Current + 6 prior
)
df = df.withColumn('moving_avg_7d', avg('revenue').over(moving_7d))

# Cumulative percentage
cum_window = (
    Window.partitionBy('department')
    .orderBy(col('salary').desc())
    .rowsBetween(Window.unboundedPreceding, Window.currentRow)
)
df = df.withColumn('cum_pct', sum('salary').over(cum_window) / sum('salary').over(Window.partitionBy('department')))
```

Best Practice: Window functions are much more efficient than self-joins for computing row-relative
values (previous value, running total, rank). Always prefer window functions over self-joins.

