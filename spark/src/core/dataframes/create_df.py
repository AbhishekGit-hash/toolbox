from pyspark.sql import SparkSession
from pyspark.sql.types import *
from utils import get_basic_spark_session

spark = get_basic_spark_session('DataFrames')

# Method 1: From list of tuples
data = [('Alice', 28, 'Engineering'), ('Bob', 35, 'Marketing'),
('Charlie', 42, 'Engineering'), ('Diana', 31, 'Sales')]
df = spark.createDataFrame(data, ['name', 'age', 'department'])
df.show()
# Output:
# +-------+---+-----------+
# | name|age| department|
# +-------+---+-----------+
# | Alice| 28|Engineering|
# | Bob| 35| Marketing|
# |Charlie| 42|Engineering|
# | Diana| 31| Sales|
# +-------+---+-----------+


# Defining schema explicitly (recommended for production)
schema = StructType([
StructField('name', StringType(), True),
StructField('age', IntegerType(), True),
StructField('department', StringType(), True),
StructField('salary', DoubleType(), True),
])
data = [('Alice', 28, 'Engineering', 95000.0),
('Bob', 35, 'Marketing', 82000.0)]
df = spark.createDataFrame(data, schema)
df.printSchema()
# root
# |-- name: string (nullable = true)
# |-- age: integer (nullable = true)
# |-- department: string (nullable = true)
# |-- salary: double (nullable = true)