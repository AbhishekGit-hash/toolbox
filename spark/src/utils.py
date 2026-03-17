from pyspark.sql import SparkSession

def get_basic_spark_session(app_name: str):
    # Basic SparkSession
    spark = SparkSession \
        .builder \
        .appName(app_name) \
        .getOrCreate()

    return spark

def get_production_spark_session():
    # SparkSession with configurations
    spark = SparkSession.builder \
        .appName('ProductionApp') \
        .config('spark.sql.shuffle.partitions', '200') \
        .config('spark.executor.memory', '4g') \
        .config('spark.driver.memory', '2g') \
        .config('spark.sql.adaptive.enabled', 'true') \
        .getOrCreate()
    return spark