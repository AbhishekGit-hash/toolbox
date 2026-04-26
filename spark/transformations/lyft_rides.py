from pyspark.sql import functions as F
from pyspark.sql.window import Window

# Step 1: total gasoline cost per hour
hourly_cost = (
    lyft_rides
    .withColumn("hour", F.hour("request_time"))
    .groupBy("hour")
    .agg(F.sum("gasoline_cost").alias("total_gas_cost"))
)

# Step 2: window to rank by highest cost
w = Window.orderBy(F.col("total_gas_cost").desc())

# Step 3: apply rank and filter top hour
result = (
    hourly_cost
    .withColumn("rnk", F.rank().over(w))
    .filter(F.col("rnk") == 1)
    .select("hour")
)

result.show()

# With limit
lyft_rides.withColumn("hour", F.hour("request_time")) \
    .groupBy("hour") \
    .agg(F.sum("gasoline_cost").alias("total_gas_cost")) \
    .orderBy(F.desc("total_gas_cost")) \
    .limit(1)