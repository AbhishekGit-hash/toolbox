from pyspark import SparkContext
from utils import get_basic_spark_session

spark = get_basic_spark_session('RDD')
sc = spark.sparkContext

# Method 1: From a Python collection
data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
rdd = sc.parallelize(data, numSlices=4) # 4 partitions


# Method 2: From a file
text_rdd = sc.textFile('hdfs:///data/logs.txt')
# Method 3: From another RDD (transformation)
squared_rdd = rdd.map(lambda x: x ** 2)
