# Spark Performance Tuning Interview Questions & Answers — SWE III Level

---

## 1. Spark Execution Model

**Q: Explain the Spark execution model — Jobs, Stages, and Tasks. Why does this matter for performance tuning?**

**A:**

When you call an **action** (e.g., `count()`, `write()`, `collect()`), Spark creates a **Job**. Each job is broken into **Stages** at shuffle boundaries. Each stage is broken into **Tasks** — one task per partition.

```
Action (e.g. df.write())
    └── Job
            ├── Stage 1 (map, filter — no shuffle)
            │       ├── Task 1 (partition 0)
            │       ├── Task 2 (partition 1)
            │       └── Task N (partition N)
            └── Stage 2 (after shuffle — e.g. groupBy)
                    ├── Task 1
                    └── Task N
```

**Why it matters for tuning:**

| Concept | Tuning implication |
|---|---|
| Too many small tasks | High scheduling overhead — increase partition size |
| Too few large tasks | Under-utilizes cluster — increase parallelism |
| Stage boundary = shuffle | Shuffles are expensive — minimize wide transformations |
| Skewed tasks | One slow task blocks the whole stage — fix data skew |

**Rule of thumb:** Aim for tasks that run between **200ms and 2 minutes**. Anything shorter means too many tiny partitions; anything longer risks OOM or stragglers.

---

## 2. Shuffles

**Q: What is a shuffle in Spark? Why is it expensive and how do you minimize it?**

**A:**

A **shuffle** is triggered by wide transformations that require data to be redistributed across partitions and executors — e.g., `groupBy`, `join`, `distinct`, `repartition`, `orderBy`.

**Why shuffles are expensive:**
- Data is **serialized, written to disk**, transferred over the network, and **deserialized** on the receiving executor.
- Disk I/O + network I/O are orders of magnitude slower than in-memory computation.
- Large shuffles cause GC pressure and can cause OOM errors.

**How to minimize shuffles:**

1. **Broadcast joins** — avoid shuffle entirely for small tables:
   ```python
   from pyspark.sql.functions import broadcast

   # Without broadcast: both tables shuffle
   df_large.join(df_small, "user_id")

   # With broadcast: small table sent to all executors, no shuffle
   df_large.join(broadcast(df_small), "user_id")
   ```
   Use when one table fits in memory (default threshold: 10MB, tunable via `spark.sql.autoBroadcastJoinThreshold`).

2. **Pre-partition data** — if two datasets are frequently joined on the same key, pre-partition and persist them:
   ```python
   df_users = df_users.repartition(200, "user_id").cache()
   df_events = df_events.repartition(200, "user_id").cache()
   # Subsequent joins on user_id avoid reshuffle
   df_users.join(df_events, "user_id")
   ```

3. **Avoid redundant shuffles** — chaining multiple `groupBy` on the same key triggers multiple shuffles. Combine aggregations in a single pass:
   ```python
   # BAD — two shuffles
   df.groupBy("user_id").agg(count("*")).groupBy("user_id").agg(sum("count"))

   # GOOD — one shuffle
   df.groupBy("user_id").agg(count("*").alias("cnt"), sum("amount").alias("total"))
   ```

4. **Use `reduceByKey` over `groupByKey`** (RDD API) — `reduceByKey` partially aggregates on the map side before shuffling, reducing data volume:
   ```python
   # BAD — sends all values over network
   rdd.groupByKey().mapValues(sum)

   # GOOD — partial aggregation before shuffle
   rdd.reduceByKey(lambda a, b: a + b)
   ```

---

## 3. Partitioning

**Q: How do you choose the right number of partitions in Spark? What are the consequences of too few or too many?**

**A:**

**Default partitions:**
- Reading from S3/HDFS: one partition per input file split (128MB default split size).
- After a shuffle: controlled by `spark.sql.shuffle.partitions` (default: **200**).

**Consequences:**

| Scenario | Problem |
|---|---|
| Too few partitions | Under-utilizes cores, large tasks risk OOM |
| Too many partitions | Scheduling overhead, many tiny files written to S3 |
| Skewed partitions | Straggler tasks block stage completion |

**How to choose the right number:**

```python
# Rule of thumb: 2–4x the number of total cores in your cluster
# Example: 10 executors × 4 cores = 40 cores → target 80–160 partitions

# Check current partition count
print(df.rdd.getNumPartitions())

# Increase partitions (triggers shuffle)
df = df.repartition(200)

# Decrease partitions without shuffle (only works to reduce)
df = df.coalesce(50)
```

**For shuffle partitions specifically:**
```python
# Set shuffle partitions based on data size
# Rule: aim for ~128MB per partition
# Example: 20GB shuffle data → 20000MB / 128MB = ~160 partitions
spark.conf.set("spark.sql.shuffle.partitions", "160")

# Spark 3.x: enable Adaptive Query Execution (AQE) to auto-tune
spark.conf.set("spark.sql.adaptive.enabled", "true")
# AQE automatically coalesces post-shuffle partitions based on actual data size
```

**Repartition vs Coalesce:**

| | `repartition(n)` | `coalesce(n)` |
|---|---|---|
| Shuffle triggered | Yes (full shuffle) | No (avoids shuffle) |
| Use case | Increase or redistribute partitions | Only reduce partitions |
| Output balance | Balanced | May be uneven |

---

## 4. Data Skew

**Q: What is data skew and how do you handle it in Spark joins and aggregations?**

**A:**

**Data skew** occurs when a small number of partition keys contain a disproportionately large amount of data. One executor gets overloaded while others sit idle.

**Detecting skew:**
```python
# Check partition sizes
df.groupBy(spark_partition_id()).count().orderBy("count", ascending=False).show()

# Or check key distribution
df.groupBy("user_id").count().orderBy("count", ascending=False).show(10)
```

**Fix 1 — Salting (for skewed joins):**
```python
import random
from pyspark.sql.functions import col, lit, concat, rand, floor, explode, array

NUM_BUCKETS = 10

# Salt the large (skewed) table
df_large = df_large.withColumn(
    "salt",
    (floor(rand() * NUM_BUCKETS)).cast("int")
).withColumn(
    "salted_key",
    concat(col("user_id"), lit("_"), col("salt"))
)

# Explode the small table to match all salt values
df_small = df_small.withColumn(
    "salt_array",
    array([lit(i) for i in range(NUM_BUCKETS)])
).withColumn("salt", explode("salt_array")) \
 .withColumn("salted_key", concat(col("user_id"), lit("_"), col("salt")))

# Join on salted key — skew is now distributed
result = df_large.join(df_small, "salted_key")
```

**Fix 2 — AQE Skew Join Optimization (Spark 3.x):**
```python
# Spark 3 AQE can detect and split skewed partitions automatically
spark.conf.set("spark.sql.adaptive.enabled", "true")
spark.conf.set("spark.sql.adaptive.skewJoin.enabled", "true")
spark.conf.set("spark.sql.adaptive.skewJoin.skewedPartitionFactor", "5")
spark.conf.set("spark.sql.adaptive.skewJoin.skewedPartitionThresholdInBytes", "256MB")
```

**Fix 3 — Two-phase aggregation (for skewed groupBy):**
```python
# Phase 1: partial aggregation with salt (reduces data per key)
df_salted = df.withColumn("salt", (rand() * 10).cast("int")) \
              .groupBy("user_id", "salt") \
              .agg(sum("amount").alias("partial_sum"))

# Phase 2: final aggregation without salt
result = df_salted.groupBy("user_id").agg(sum("partial_sum").alias("total"))
```

---

## 5. Caching and Persistence

**Q: When should you cache a DataFrame in Spark? What storage levels are available?**

**A:**

**Cache when:**
- The same DataFrame is used **multiple times** in your pipeline.
- Recomputation is expensive (e.g., involves a large shuffle or complex transformation).
- You are running **iterative algorithms** (ML training loops).

**Do NOT cache when:**
- The DataFrame is used only once — caching wastes memory and serialization time.
- The DataFrame is very large and doesn't fit in memory — spilling to disk causes more overhead than recomputing.

**Storage levels:**

```python
from pyspark import StorageLevel

# Default cache — MEMORY_AND_DISK (deserialized in JVM heap)
df.cache()

# Explicit storage levels
df.persist(StorageLevel.MEMORY_ONLY)          # Fast, risk of OOM
df.persist(StorageLevel.MEMORY_AND_DISK)      # Spills to disk if needed (default)
df.persist(StorageLevel.MEMORY_ONLY_SER)      # Serialized — less memory, slower access
df.persist(StorageLevel.MEMORY_AND_DISK_SER)  # Serialized + disk spill
df.persist(StorageLevel.DISK_ONLY)            # Slowest, for very large datasets
df.persist(StorageLevel.OFF_HEAP)             # Off-heap memory (avoids GC pressure)
```

**Always unpersist when done:**
```python
df.unpersist()
```

**Practical example:**
```python
# BAD — df_joined is computed twice
df_joined = df_users.join(df_events, "user_id")
count_by_region = df_joined.groupBy("region").count()
total_revenue = df_joined.groupBy("region").agg(sum("amount"))

# GOOD — compute once, cache, reuse
df_joined = df_users.join(df_events, "user_id").cache()
count_by_region = df_joined.groupBy("region").count()
total_revenue = df_joined.groupBy("region").agg(sum("amount"))
df_joined.unpersist()
```

---

## 6. Broadcast Variables and Accumulators

**Q: What are broadcast variables and accumulators in Spark? When do you use each?**

**A:**

### Broadcast Variables
Used to efficiently distribute a **read-only** large variable to all executors — sent once, cached locally.

```python
# Without broadcast: lookup dict serialized and sent with every task
lookup = {"US": "United States", "IN": "India"}
df.filter(col("country_code").isin(list(lookup.keys())))

# With broadcast: sent once to each executor, not per-task
lookup_bc = spark.sparkContext.broadcast({"US": "United States", "IN": "India"})

from pyspark.sql.functions import udf
from pyspark.sql.types import StringType

@udf(StringType())
def expand_country(code):
    return lookup_bc.value.get(code, "Unknown")

df.withColumn("country_name", expand_country(col("country_code")))
```

**Use when:** You have a large dictionary, ML model, or config that every task needs to access.

### Accumulators
Used to **aggregate values across tasks** back to the driver — write-only from executors, read-only on driver.

```python
# Track bad records without collecting them to driver
bad_record_count = spark.sparkContext.accumulator(0)

def validate_row(row):
    if row["amount"] < 0:
        bad_record_count.add(1)
        return False
    return True

df.rdd.filter(validate_row).toDF()
print(f"Bad records found: {bad_record_count.value}")
```

**Caution:** Accumulators are **not reliable for transformations** (lazy eval may cause tasks to re-run). Use only inside actions or `foreach`.

---

## 7. Memory Management and GC Tuning

**Q: How is memory managed in a Spark executor? What causes OOM errors and how do you fix them?**

**A:**

**Spark executor memory regions (Unified Memory Model):**

```
Total Executor Memory
    ├── Reserved Memory (300MB fixed — Spark internals)
    ├── User Memory   (spark.memory.fraction complement — user data structures)
    └── Spark Memory  (spark.memory.fraction = 0.6 default)
            ├── Execution Memory (shuffles, sorts, joins, aggregations)
            └── Storage Memory   (cached RDDs/DataFrames)
            (these two borrow from each other dynamically)
```

**Common OOM causes and fixes:**

| Cause | Fix |
|---|---|
| Too many cached DataFrames | Unpersist unused DataFrames |
| Large shuffle partitions | Increase `spark.sql.shuffle.partitions` to reduce per-partition size |
| `collect()` on large data | Use `take(n)` or write to storage instead |
| UDFs holding large objects | Use broadcast variables or vectorized Pandas UDFs |
| Data skew | Salt keys, use AQE skew join |

**Tuning memory configs:**
```python
# Increase executor memory
spark = SparkSession.builder \
    .config("spark.executor.memory", "8g") \
    .config("spark.executor.memoryOverhead", "2g")  # For off-heap, Python worker, etc.
    .config("spark.memory.fraction", "0.8")          # More memory for Spark operations
    .config("spark.memory.storageFraction", "0.3")   # Portion of Spark memory for caching
    .getOrCreate()
```

**GC tuning:**
```python
# G1GC is recommended for large heaps (>4GB executor memory)
.config("spark.executor.extraJavaOptions",
        "-XX:+UseG1GC -XX:InitiatingHeapOccupancyPercent=35")
```

---

## 8. Adaptive Query Execution (AQE)

**Q: What is Adaptive Query Execution in Spark 3.x? What optimizations does it enable?**

**A:**

**AQE** allows Spark to **re-optimize the query plan at runtime** using actual shuffle statistics, rather than relying solely on static estimates at plan time.

**Enable AQE:**
```python
spark.conf.set("spark.sql.adaptive.enabled", "true")  # Default: true in Spark 3.2+
```

**Three main optimizations AQE provides:**

### 1. Dynamic Coalescing of Shuffle Partitions
After a shuffle, AQE merges small partitions into larger ones — avoids the "200 tiny partitions" problem.

```python
spark.conf.set("spark.sql.adaptive.coalescePartitions.enabled", "true")
spark.conf.set("spark.sql.adaptive.advisoryPartitionSizeInBytes", "128MB")
spark.conf.set("spark.sql.adaptive.coalescePartitions.minPartitionNum", "1")
```

### 2. Dynamic Switching of Join Strategies
If a table turns out to be small enough after filtering, AQE can switch a Sort-Merge Join to a Broadcast Hash Join at runtime.

```python
spark.conf.set("spark.sql.adaptive.localShuffleReader.enabled", "true")
```

### 3. Dynamic Skew Join Optimization
AQE detects skewed partitions and splits them into smaller sub-tasks automatically.

```python
spark.conf.set("spark.sql.adaptive.skewJoin.enabled", "true")
spark.conf.set("spark.sql.adaptive.skewJoin.skewedPartitionFactor", "5")
spark.conf.set("spark.sql.adaptive.skewJoin.skewedPartitionThresholdInBytes", "256MB")
```

**Before vs After AQE:**

| Scenario | Without AQE | With AQE |
|---|---|---|
| 200 shuffle partitions, most empty | 200 tiny tasks | Auto-coalesced to ~20 optimal tasks |
| Small table after filter, planned as SMJ | Expensive Sort-Merge Join | Switched to Broadcast Hash Join |
| Skewed partition 10x larger than others | One straggler task | Skewed partition split into sub-tasks |

---

## 9. Join Strategies

**Q: What join strategies does Spark support? How does Spark choose between them and how can you influence the choice?**

**A:**

**Spark join strategies:**

| Strategy | When used | Shuffle required |
|---|---|---|
| **Broadcast Hash Join (BHJ)** | One table fits in memory | No — small table broadcast to all executors |
| **Sort-Merge Join (SMJ)** | Both tables large, join key sortable | Yes — both tables shuffled and sorted |
| **Shuffle Hash Join (SHJ)** | One table smaller, no sort needed | Yes — smaller table hashed in memory |
| **Cartesian Join** | No join condition (cross join) | Yes — very expensive |
| **Broadcast Nested Loop** | Non-equi joins with small table | Partial broadcast |

**How Spark chooses:** Based on table size statistics from the Glue/Hive catalog or `ANALYZE TABLE`. If stats are stale or missing, Spark may make a suboptimal choice.

**Force a join strategy with hints:**
```python
from pyspark.sql.functions import broadcast

# Force broadcast join
df_result = df_large.join(broadcast(df_small), "user_id")

# SQL hint syntax
spark.sql("""
    SELECT /*+ BROADCAST(small_table) */ *
    FROM large_table
    JOIN small_table ON large_table.id = small_table.id
""")

# Force sort-merge join (override broadcast threshold)
spark.sql("""
    SELECT /*+ MERGE(large_table) */ *
    FROM large_table
    JOIN another_large_table ON large_table.id = another_large_table.id
""")
```

**Tune broadcast threshold:**
```python
# Default is 10MB — increase for larger dimension tables
spark.conf.set("spark.sql.autoBroadcastJoinThreshold", "50MB")

# Disable auto-broadcast entirely
spark.conf.set("spark.sql.autoBroadcastJoinThreshold", "-1")
```

---

## 10. Reading and Writing Efficiently

**Q: What are best practices for reading and writing data efficiently in Spark, especially with S3?**

**A:**

### Reading efficiently

**Use columnar formats (Parquet/ORC):**
```python
# Parquet with predicate pushdown and column pruning
df = spark.read.parquet("s3://bucket/events/")

# Only reads columns needed — avoids deserializing entire rows
df.select("user_id", "event_type").filter(col("event_date") == "2024-01-01")
```

**Partition pruning — ensure filter is on partition column:**
```python
# Spark pushes this filter down to S3 — reads only matching partitions
df = spark.read.parquet("s3://bucket/events/") \
    .filter(col("event_date").between("2024-01-01", "2024-01-31"))
```

**Avoid small files — use `basedOnWholeStageCodegen`:**
```python
# Increase split size to reduce number of tasks for many small files
spark.conf.set("spark.sql.files.maxPartitionBytes", "256MB")  # default 128MB
spark.conf.set("spark.sql.files.openCostInBytes", "8MB")
```

### Writing efficiently

**Control output file count:**
```python
# BAD — 200 files written (one per shuffle partition)
df.write.parquet("s3://bucket/output/")

# GOOD — coalesce before writing to reduce file count
df.coalesce(10).write.parquet("s3://bucket/output/")

# BETTER for large datasets — repartition by output key for sorted output
df.repartition(50, "event_date").write \
    .partitionBy("event_date") \
    .parquet("s3://bucket/output/")
```

**Avoid S3 rename problem:**
```python
# Use EMRFS or configure committer to avoid slow S3 rename operations
spark.conf.set("spark.hadoop.fs.s3a.committer.name", "magic")
spark.conf.set("spark.sql.sources.commitProtocolClass",
               "org.apache.spark.internal.io.cloud.PathOutputCommitProtocol")
```

**Compression:**
```python
# Snappy: fast, splittable (recommended for Parquet)
df.write.option("compression", "snappy").parquet("s3://bucket/output/")

# ZSTD: better compression ratio, good for cold storage
df.write.option("compression", "zstd").parquet("s3://bucket/output/")
```

---

## 11. UDFs and Vectorized UDFs

**Q: What is the performance cost of Python UDFs in Spark? How do Pandas UDFs (vectorized UDFs) improve this?**

**A:**

**Python UDF cost:**

Each row in a Python UDF goes through:
1. Serialize JVM row → Python pickle
2. Send over local socket to Python worker
3. Execute Python function
4. Serialize result → send back to JVM
5. Deserialize in JVM

This **row-by-row serialization** is extremely expensive for large datasets.

```python
# BAD — Python UDF: row-by-row serialization
from pyspark.sql.functions import udf
from pyspark.sql.types import DoubleType

@udf(DoubleType())
def slow_discount(price, pct):
    return price * (1 - pct / 100)

df.withColumn("discounted", slow_discount(col("price"), col("discount_pct")))
```

**Pandas UDF (vectorized) — much faster:**

Pandas UDFs use **Apache Arrow** for zero-copy columnar data transfer between JVM and Python. Entire batches are processed at once.

```python
from pyspark.sql.functions import pandas_udf
from pyspark.sql.types import DoubleType
import pandas as pd

# GOOD — Pandas UDF: batch columnar transfer via Apache Arrow
@pandas_udf(DoubleType())
def fast_discount(price: pd.Series, pct: pd.Series) -> pd.Series:
    return price * (1 - pct / 100)

df.withColumn("discounted", fast_discount(col("price"), col("discount_pct")))
```

**Performance comparison:**

| UDF Type | Serialization | Throughput | Use case |
|---|---|---|---|
| Python UDF | Row-by-row pickle | Slowest | Avoid if possible |
| Pandas UDF (scalar) | Columnar Arrow batches | 10–100x faster | Most custom logic |
| Pandas UDF (grouped) | Per-group DataFrame | Fast for group ops | Window/group aggregations |
| Spark SQL functions | JVM native, no Python | Fastest | Always prefer built-ins |

**Always prefer built-in Spark SQL functions when possible:**
```python
from pyspark.sql.functions import when, regexp_extract, date_format

# These run entirely in JVM — no Python overhead at all
df.withColumn("discounted", col("price") * (1 - col("discount_pct") / 100))
```

---

## 12. Speculative Execution and Straggler Tasks

**Q: What is speculative execution in Spark? When does it help and when can it hurt?**

**A:**

**Speculative execution** — Spark launches a duplicate copy of a slow (straggler) task on a different executor. Whichever finishes first wins; the other is killed.

**Enable speculative execution:**
```python
spark.conf.set("spark.speculation", "true")
spark.conf.set("spark.speculation.multiplier", "1.5")   # Task is 1.5x slower than median
spark.conf.set("spark.speculation.quantile", "0.75")    # 75% of tasks must complete first
spark.conf.set("spark.speculation.minTaskRuntime", "60s") # Don't speculate tasks < 60s old
```

**When it helps:**
- Transient hardware issues (slow disk, network hiccup on one node).
- Uneven cluster load causing one executor to be slower.

**When it hurts:**
- **Data skew** — the straggler is slow because it has 10x more data. A speculative copy will also be slow. Fix skew instead.
- **Non-idempotent writes** — if the task writes to an external system (e.g., a database), two copies running simultaneously cause duplicates.
- **Memory pressure** — launching duplicate tasks increases memory load, potentially causing more OOMs.

**Diagnosis flow:**
```
Straggler task detected
    ├── Is one partition much larger? → Fix data skew (salt keys / AQE)
    ├── Is it a hardware issue (random)? → Enable speculative execution
    └── Is it a UDF bottleneck? → Optimize UDF or switch to Pandas UDF
```

---

## 13. Spark Configuration Tuning Reference

**Q: What are the most impactful Spark configuration parameters for performance tuning? Walk me through each.**

**A:**

```python
spark = SparkSession.builder \
    # --- Executor sizing ---
    .config("spark.executor.instances", "20") \
    .config("spark.executor.cores", "4") \          # 4 cores per executor
    .config("spark.executor.memory", "16g") \        # 16GB heap per executor
    .config("spark.executor.memoryOverhead", "4g") \ # Off-heap (Python, native libs)

    # --- Driver sizing ---
    .config("spark.driver.memory", "8g") \
    .config("spark.driver.maxResultSize", "4g") \    # Max size of collect() result

    # --- Parallelism ---
    .config("spark.default.parallelism", "160") \             # RDD default parallelism
    .config("spark.sql.shuffle.partitions", "160") \           # Shuffle partition count
    .config("spark.sql.files.maxPartitionBytes", "256MB") \    # Max partition size when reading

    # --- Adaptive Query Execution ---
    .config("spark.sql.adaptive.enabled", "true") \
    .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
    .config("spark.sql.adaptive.skewJoin.enabled", "true") \

    # --- Broadcast ---
    .config("spark.sql.autoBroadcastJoinThreshold", "50MB") \

    # --- Serialization ---
    .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \ # Faster than Java serializer
    .config("spark.kryo.registrationRequired", "false") \

    # --- Dynamic allocation (auto-scale executors) ---
    .config("spark.dynamicAllocation.enabled", "true") \
    .config("spark.dynamicAllocation.minExecutors", "2") \
    .config("spark.dynamicAllocation.maxExecutors", "50") \
    .config("spark.dynamicAllocation.executorIdleTimeout", "60s") \

    # --- GC ---
    .config("spark.executor.extraJavaOptions",
            "-XX:+UseG1GC -XX:InitiatingHeapOccupancyPercent=35") \

    .getOrCreate()
```

**Key rules of thumb:**

| Parameter | Guideline |
|---|---|
| `executor.cores` | 4–5 cores per executor is optimal. More causes GC contention. |
| `executor.memory` | Leave headroom — don't allocate 100% of node memory |
| `shuffle.partitions` | `total_data_size_MB / 128` — tune to ~128MB per partition |
| `autoBroadcastJoinThreshold` | Increase cautiously — broadcasting too-large tables causes OOM |
| `spark.serializer` | Always use Kryo — 2–10x faster than default Java serializer |

---

## 14. Debugging Performance with Spark UI

**Q: How do you use the Spark UI to identify performance bottlenecks?**

**A:**

**Key tabs and what to look for:**

### Jobs Tab
- Identify which jobs are slow.
- Look for jobs with a high number of failed/retried tasks.

### Stages Tab
- Find stages with long durations.
- Check the **task distribution** — a long tail indicates data skew.
- Look for stages with large **shuffle read/write** sizes.

### Tasks Tab (within a Stage)
```
Task duration distribution:
  Min: 5s  Median: 8s  Max: 4m 32s  ← Large gap = skew or straggler
```

### Storage Tab
- See which DataFrames are cached and how much memory they occupy.
- Check for spill to disk — indicates insufficient memory.

### SQL Tab
- Shows the physical query plan with metrics per operator.
- Look for:
  - **SortMergeJoin** where a **BroadcastHashJoin** would be faster.
  - **Exchange** nodes (each one = a shuffle).
  - High **rows filtered** at late stages (push filters earlier).

**Reading the DAG visualization:**
```
[FileScan] → [Filter] → [Exchange (shuffle)] → [HashAggregate] → [Exchange] → [HashAggregate]
                                 ↑                                      ↑
                          shuffle boundary                        shuffle boundary
```

Each `Exchange` node is a shuffle — minimize these.

**Practical debugging checklist:**
1. Are tasks balanced? (check task duration distribution)
2. Is there excessive shuffle data? (check shuffle read/write size per stage)
3. Are there many small tasks? (tune `shuffle.partitions`)
4. Is data spilling to disk? (check spill metrics in Storage tab)
5. Are joins using the right strategy? (check SQL tab physical plan)

---

## 15. Design Question: Optimize a Slow Spark Pipeline

**Q: You have a Spark job that processes 500GB of daily clickstream data. It's taking 3 hours and timing out. Walk me through how you'd diagnose and fix it.**

**A:**

**Step 1 — Diagnose using Spark UI:**
- Check Stages tab for the slowest stage.
- Check task duration distribution for skew.
- Check shuffle read/write sizes.
- Check for disk spill in the Storage tab.

**Step 2 — Apply fixes based on findings:**

```python
# Fix 1: Enable AQE — handles skew, partition coalescing, join strategy switching automatically
spark.conf.set("spark.sql.adaptive.enabled", "true")
spark.conf.set("spark.sql.adaptive.skewJoin.enabled", "true")
spark.conf.set("spark.sql.adaptive.coalescePartitions.enabled", "true")

# Fix 2: Tune shuffle partitions for 500GB dataset
# 500GB / 128MB per partition ≈ 4000 partitions
spark.conf.set("spark.sql.shuffle.partitions", "4000")

# Fix 3: Broadcast small dimension tables
df_result = df_clickstream.join(broadcast(df_campaigns), "campaign_id")

# Fix 4: Push filters early — reduce data before expensive joins
df_filtered = df_clickstream \
    .filter(col("event_date") == "2024-01-01") \  # partition pruning
    .filter(col("event_type") == "click") \        # row filtering
    .select("user_id", "campaign_id", "amount")    # column pruning

# Fix 5: Replace Python UDFs with Pandas UDFs or built-in functions
# BAD
@udf(DoubleType())
def normalize(val): return val / 1000.0

# GOOD
df_filtered = df_filtered.withColumn("amount_k", col("amount") / 1000.0)

# Fix 6: Cache intermediate result used multiple times
df_enriched = df_filtered.join(broadcast(df_campaigns), "campaign_id").cache()
summary_by_region = df_enriched.groupBy("region").agg(sum("amount_k"))
summary_by_type = df_enriched.groupBy("event_type").count()
df_enriched.unpersist()

# Fix 7: Use Kryo serializer
spark.conf.set("spark.serializer", "org.apache.spark.serializer.KryoSerializer")

# Fix 8: Optimize output — write partitioned Parquet
df_enriched \
    .repartition(200, "event_date") \
    .write \
    .partitionBy("event_date") \
    .option("compression", "snappy") \
    .parquet("s3://bucket/output/clickstream/")
```

**Expected improvements:**

| Fix | Expected gain |
|---|---|
| AQE + skew join | Eliminates straggler tasks |
| Broadcast join | Removes one large shuffle |
| Early filter + column pruning | Reduces data volume 5–10x |
| Pandas UDF over Python UDF | 10–100x faster per-row ops |
| Kryo serializer | 2–5x faster serialization |
| Tuned shuffle partitions | Eliminates tiny/huge partition extremes |

---

*Want deeper coverage on Spark Streaming performance, Delta Lake + Spark tuning, or Spark on EMR/Glue specifics? Let me know!*