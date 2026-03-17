from utils import get_basic_spark_session

spark = get_basic_spark_session('DataFrames')

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