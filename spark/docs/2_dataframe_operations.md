
## Selecting Columns

```python
from pyspark.sql import functions as F

# Select with transformation
df.select(
    F.col('name'),
    F.col('salary'),
    (F.col('salary') * 0.1).alias('bonus') # Calculated column
)
```

## Filtering Records

```py
from pyspark.sql import functions as F

# Multiple conditions (AND)
df.filter((F.col('age') > 25) & (F.col('department') == 'Engineering'))
# Multiple conditions (OR)
df.filter((F.col('age') > 40) | (F.col('salary') > 100000))

# NOT condition
df.filter(~F.col('name').startswith('A'))

# IN condition
df.filter(F.col('department').isin('Engineering', 'Sales'))

# NULL checks
df.filter(F.col('email').isNotNull())
df.filter(F.col('phone').isNull())

# String patterns
df.filter(F.col('name').like('%son'))
df.filter(F.col('name').contains('Ali'))
df.filter(F.col('email').rlike('^[a-z]+@.*\.com$')) # Regex
```

## Adding and Modifying Columns

```py
from pyspark.sql.functions import col, lit, when, upper, concat

# Add new column
df = df.withColumn('bonus', col('salary') * 0.1)

# Add constant column
df = df.withColumn('country', lit('USA'))

# Modify existing column
df = df.withColumn('name', upper(col('name')))

# Conditional column (CASE WHEN)
df = df.withColumn('level',
    when(col('salary') > 100000, 'Senior')
    .when(col('salary') > 70000, 'Mid')
    .otherwise('Junior')
)

# Concatenate columns
df = df.withColumn('full_info', concat(col('name'), lit(' - '), col('department')))

# Rename column
df = df.withColumnRenamed('name', 'employee_name')

# Drop columns
df = df.drop('temp_col', 'debug_col')
```

## Sorting

Warning: Sorting is expensive in distributed systems because data from all partitions must be
compared. Avoid unnecessary sorts, especially before a write operation where order does not matter.

```py
from pyspark.sql.functions import col, asc, desc

# Simple sort
df.orderBy('salary') # Ascending (default)

df.orderBy(col('salary').desc()) # Descending

# Multi-column sort
df.orderBy(
    col('department').asc(),
    col('salary').desc()
)
```