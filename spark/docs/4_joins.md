## Join Syntax

```py
from pyspark.sql import functions as F

e = employee.alias("e")
m = employee.alias("m")

join_condition = (
    (F.col("e.manager_id") == F.col("m.emp_id")) &
    (F.col("e.dept") == F.col("m.dept"))
)

result = e.join(m, join_condition, "inner")
```

## Join Performance & Optimization

### Broadcast Join (Small + Large table)
When one table is small (under ~10 MB), Spark can broadcast it to all executors, avoiding an
expensive shuffle.

```py
from pyspark.sql.functions import broadcast, col

l = large_df.alias("l")
s = small_lookup_df.alias("s")

join_condition = (
    (col("l.id") == col("s.id")) &
    (col("l.country") == col("s.country")) &
    (col("l.dept") == col("s.dept"))
)

result = l.join(broadcast(s), join_condition, "inner")

# Spark auto-broadcasts tables under threshold
# Default: spark.sql.autoBroadcastJoinThreshold = 10MB
spark.conf.set('spark.sql.autoBroadcastJoinThreshold', '50m')
```

Best Practice: Always broadcast dimension/lookup tables when joining with fact tables. A 50 MB
broadcast avoids shuffling 500 GB of fact data across the network.

## Sort-Merge Join (Large + Large table)
For large-to-large joins, Spark uses Sort-Merge Join. Both tables are sorted by the join key and
then merged. This requires a shuffle (data redistribution), which is expensive.

## Handling Skewed Joins

Data skew happens when some join keys have far more records than others (e.g., 90% of
orders belong to 10 customers). This creates a bottleneck where one executor does most of the
work.

```py
# Enable Adaptive Query Execution (handles skew automatically)
spark.conf.set('spark.sql.adaptive.enabled', 'true')
spark.conf.set('spark.sql.adaptive.skewJoin.enabled', 'true')

# Manual approach: salt the key
from pyspark.sql.functions import lit, rand, floor, concat

salt_range = 10
salted_big = big_df.withColumn('salt', floor(rand() * salt_range))
salted_big = salted_big.withColumn('salted_key',
concat(col('join_key'), lit('_'), col('salt')))
```

