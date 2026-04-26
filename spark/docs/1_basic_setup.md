
## Spark Session

```python
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
```

## Explict Schema Defination

```python
# Defining schema explicitly (recommended for production)
schema = StructType([
        StructField('name', StringType(), True),
        StructField('age', IntegerType(), True),
        StructField('department', StringType(), True),
        StructField('salary', DoubleType(), True),
    ])

data = [('Alice', 28, 'Engineering', 95000.0), ('Bob', 35, 'Marketing', 82000.0)]
df = spark.createDataFrame(data, schema)
df.printSchema()
```

## Read Data

```python
# CSV
df = spark.read.csv('data.csv', header=True, inferSchema=True)
df = spark.read.option('header', True).schema(my_schema).csv('data.csv')

# JSON
df = spark.read.json('data.json')
df = spark.read.option('multiLine', True).json('nested.json')

# Parquet (preferred format for big data)
df = spark.read.parquet('data.parquet')

# Delta Lake
df = spark.read.format('delta').load('delta_table/')

# JDBC (Database)
df = spark.read.format('jdbc') \
.option('url', 'jdbc:postgresql://host:5432/db') \
.option('dbtable', 'public.users') \
.option('user', 'admin') \
.option('password', 'secret') \
.load()
```

## Write Data

```python
# Partitioned write (crucial for performance)
df.write.mode('overwrite') \
.partitionBy('year', 'month') \
.parquet('output/partitioned/')
```

