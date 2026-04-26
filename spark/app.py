from pyspark.sql import SparkSession

# Basic SparkSession
spark = SparkSession.builder \
.appName('MyFirstApp') \
.getOrCreate()
# SparkSession with configurations
spark = SparkSession.builder \
.appName('ProductionApp') \
.config('spark.sql.shuffle.partitions', '200') \
.config('spark.executor.memory', '4g') \
.config('spark.driver.memory', '2g') \
.config('spark.sql.adaptive.enabled', 'true') \
.getOrCreate()