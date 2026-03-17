# Write modes: 'overwrite', 'append', 'ignore', 'error'
# Parquet (columnar, compressed - best for analytics)
df.write.mode('overwrite').parquet('output/data.parquet')
# Partitioned write (crucial for performance)
df.write.mode('overwrite') \
.partitionBy('year', 'month') \
.parquet('output/partitioned/')
# CSV
df.write.mode('overwrite') \
.option('header', True) \
.csv('output/data.csv')
# Single file output (use with caution on large data)
df.coalesce(1).write.mode('overwrite').csv('output/single/')