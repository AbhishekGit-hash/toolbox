## Simple Aggregations

```py
from pyspark.sql import functions as F

# Aggregate entire DataFrame
df.select(
    F.count('*').alias('total_rows'),
    F.countDistinct('department').alias('unique_depts'),
    F.avg('salary').alias('avg_salary'),
    F.max('salary').alias('max_salary'),
    F.min('salary').alias('min_salary'),
    F.sum('salary').alias('total_payroll'),
    F.stddev('salary').alias('salary_stddev'),
).show()
```

## GroupBy Aggregations

```py
# Group by multiple columns
result = (
    df.groupBy('department', 'level')
    .agg(
        F.count('*').alias('count'),
        F.sum('salary').alias('total_salary'),
    )
    .orderBy('department', 'level')
    .show()
)
```

## Pivot Tables

Pivot tables rotate rows into columns, which is very useful for creating summary reports.

Best Practice: Always specify the values list in pivot() like .pivot('col', ['val1', 'val2']). Without it,
Spark makes an extra pass over the data to discover unique values, which is expensive on large
datasets.

```py
# Pivot: departments as rows, quarters as columns
pivot_df = (
    df.groupBy('department')
    .pivot('quarter', ['Q1', 'Q2', 'Q3', 'Q4'])
    .agg(F.sum('revenue'))
)
```

## Rollup and Cube

Rollup and Cube are advanced grouping operations that create subtotals and grand totals
automatically.

```py
# Rollup: Hierarchical subtotals (left to right)
df.rollup('department', 'level') \
.agg(count('*').alias('count'), sum('salary').alias('total')) \
.orderBy('department', 'level') \
.show()
# Shows: grand total, department totals, department+level combos
# Cube: All possible combinations of subtotals
df.cube('department', 'level') \
.agg(count('*').alias('count')) \
.show()
# Shows: grand total, dept totals, level totals, dept+level combos
```

