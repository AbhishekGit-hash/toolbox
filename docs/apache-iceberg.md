# Apache Iceberg Interview Questions & Answers

---

## 1. What is Apache Iceberg and why was it created?

**Q: What is Apache Iceberg and what problems does it solve?**

**A:** Apache Iceberg is an **open table format** for huge analytic datasets. It was originally created at Netflix to solve fundamental problems with Hive tables at scale.

| Problem (Hive) | Iceberg Solution |
|---|---|
| No ACID transactions | Full <mark>ACID</mark> with snapshot isolation |
| Slow metadata (MSCK REPAIR) | Fast metadata via manifest files |
| No schema evolution | <mark>Safe schema & partition evolution</mark> |
| Unsafe concurrent writes | <mark>Optimistic concurrency control</mark> |
| No partition awareness in queries | <mark>Hidden partitioning</mark> |
| No time travel | <mark>Snapshot-based time travel</mark> |

**Core idea:** Iceberg tracks **exactly which files belong to a table** at any point in time using a tree of metadata files — instead of relying on directory listing like Hive.

---

## 2. Iceberg Metadata Architecture

**Q: Explain the Iceberg metadata architecture. What are the layers and what does each contain?**

**A:** Iceberg has a **3-layer metadata hierarchy:**

```
Catalog (pointer to latest metadata)
    └── metadata.json  (table metadata file)
            ├── Schema history
            ├── Partition specs
            └── Snapshot list
                    └── manifest-list (avro)
                            └── manifest files (avro)
                                    └── data files (Parquet/ORC/Avro)
```

**Layer by layer:**

1. **Catalog** — Stores the pointer to the current `metadata.json`. Can be Glue, Hive Metastore, Nessie, REST catalog, or JDBC.

2. **Metadata file (`metadata.json`)** — Contains <mark>table schema, partition spec, list of snapshots, and current snapshot ID</mark>.

3. **Manifest list** — <mark>Per snapshot</mark>; lists <mark>all manifest files</mark> and their <mark>summary stats</mark> (min/max values, record counts, partition ranges).

4. **Manifest file** — Lists individual <mark>data files with column-level statistics</mark> (null counts, lower/upper bounds).

5. **Data files** — Actual Parquet/ORC/Avro files stored in S3/HDFS/GCS.

**Why this matters:** Query engines use manifest statistics to **skip entire files and partitions** without opening them — this is called *metadata filtering* or *data skipping*.

---

## 3. Hidden Partitioning

**Q: What is Hidden Partitioning in Iceberg and how does it differ from Hive partitioning?**

**A:** In **Hive**, partitioning is user-managed and exposed in queries:

```sql
-- User must manually filter on partition column
-- Full scan happens silently if partition filter is missing
SELECT * FROM events WHERE dt = '2024-01-01'
```

In **Iceberg**, partitioning is **hidden** — <mark>the engine applies partition transforms automatically</mark>:

```sql
-- Iceberg partition spec (defined once at table creation)
PARTITIONED BY (days(event_timestamp))

-- Query — no partition column needed
SELECT * FROM events WHERE event_timestamp >= '2024-01-01'
-- Iceberg automatically maps this to the correct partitions
```

**Available partition transforms:**

| Transform | Example | Output |
|---|---|---|
| `identity(col)` | `identity(region)` | Exact value |
| `days(ts)` | `days(event_time)` | 2024-01-01 |
| `hours(ts)` | `hours(event_time)` | 2024-01-01-13 |
| `months(ts)` | `months(event_time)` | 2024-01 |
| `years(ts)` | `years(event_time)` | 2024 |
| `bucket(N, col)` | `bucket(16, user_id)` | 0–15 |
| `truncate(W, col)` | `truncate(3, name)` | First 3 chars |

---

## 4. Partition Evolution

**Q: What is Partition Evolution in Iceberg? How does it solve the Hive problem?**

**A:** **The Hive problem:** Changing a partition scheme requires rewriting all historical data — expensive and risky.

**Iceberg solution:** Partition specs are versioned. Old data retains its old spec; new data uses the new spec. The query engine handles both transparently.

```sql
-- Original table partitioned by months
CREATE TABLE events (event_time TIMESTAMP, ...)
PARTITIONED BY (months(event_time));

-- After 1 year, switch to days for finer granularity — no rewrite needed
ALTER TABLE events
SET PARTITION SPEC (days(event_time));
```

- Data written **before** the change remains in monthly partitions.
- Data written **after** the change goes into daily partitions.
- Queries work seamlessly across both — Iceberg resolves the correct partition spec per file via manifest metadata.

**No data rewrite. No downtime.**

---

## 5. ACID Transactions

**Q: How does Iceberg implement ACID transactions? What concurrency model does it use?**

**A:** Iceberg uses **Optimistic Concurrency Control (OCC)** with **snapshot isolation**.

**Write flow:**
1. Writer reads the current snapshot.
2. Writer creates new data files in S3.
3. Writer creates a new manifest file pointing to the new data files.
4. Writer attempts to **atomically swap** the catalog pointer from old snapshot → new snapshot using a **compare-and-swap (CAS)** operation.
5. If another writer committed first (conflict), the write retries or fails with a conflict error.

**Read flow:**
- Readers always read from a **committed snapshot** — they never see partial writes.
- A write in progress is invisible until the CAS succeeds.

**Isolation levels:**

| Level | Behavior |
|---|---|
| Snapshot isolation (default) | Reads see a consistent snapshot at query start |
| Serializable | Conflict detection on overlapping row ranges |

**Concurrent write conflict resolution:**
- **Append-only operations (INSERT):** Always succeed — no conflicts possible.
- **Overwrites / deletes:** May conflict — Iceberg retries with configurable retry logic.

---

## 6. Time Travel and Rollback

**Q: How does time travel work in Iceberg? How do you roll back a table to a previous state?**

**A:** Every write creates a new **snapshot**. Old snapshots are retained until explicitly expired.

**Time travel by snapshot ID:**
```sql
SELECT * FROM events VERSION AS OF 5678901234;
```

**Time travel by timestamp:**
```sql
SELECT * FROM events TIMESTAMP AS OF '2024-01-15 10:00:00';
```

**Rollback a table to a previous snapshot:**
```sql
-- By snapshot ID
CALL catalog.system.rollback_to_snapshot('db.events', 5678901234);

-- By timestamp
CALL catalog.system.rollback_to_timestamp('db.events', TIMESTAMP '2024-01-15 10:00:00');
```

**Use cases:**
- Recovering from accidental `DELETE` or `UPDATE`
- Auditing what data looked like at a specific time
- Reproducing ML training datasets exactly
- Debugging data quality regressions

**Snapshot expiration (important for cost control):**
```sql
CALL catalog.system.expire_snapshots(
  table => 'db.events',
  older_than => TIMESTAMP '2024-01-20 00:00:00',
  retain_last => 5
);
```

Without expiration, old data files accumulate and storage costs grow indefinitely.

---

## 7. Row-Level Deletes (Iceberg V2)

**Q: What are the three delete modes in Iceberg V2? When would you use each?**

**A:** Iceberg V2 introduced **row-level deletes** via three strategies:

### Copy-on-Write (CoW)
- On DELETE/UPDATE, the affected data files are **rewritten** with the rows removed.
- **Read performance:** Fast — no extra lookup overhead.
- **Write performance:** Slow — rewrites entire files.
- **Best for:** Read-heavy tables with infrequent updates.

### Merge-on-Read (MoR)
- On DELETE/UPDATE, a **delete file** is written alongside the original data file.
- At read time, data files and delete files are merged.
- **Read performance:** Slightly slower due to merge overhead.
- **Write performance:** Fast — no file rewrite.
- **Best for:** Write-heavy, CDC, or streaming tables.

### Delete file types in MoR:

| Type | How it works |
|---|---|
| **Positional delete** | Records file path + row position to delete |
| **Equality delete** | Records column values — deletes all rows matching the predicate |

**Compaction:** After accumulating many delete files, run compaction to rewrite files and eliminate read overhead:

```sql
CALL catalog.system.rewrite_data_files(
  table => 'db.events',
  strategy => 'binpack',
  options => map('min-input-files', '5')
);
```

---

## 8. Schema Evolution

**Q: What schema changes does Iceberg support safely? What is the role of column IDs?**

**A:**

| Operation | Safe? | Notes |
|---|---|---|
| Add column | ✅ Yes | New column reads as NULL for old files |
| Drop column | ✅ Yes | Old files retain data; reads return NULL |
| Rename column | ✅ Yes | Tracked by column ID, not name |
| Reorder columns | ✅ Yes | Logical reorder only |
| Widen type | ✅ Yes | e.g., INT → LONG, FLOAT → DOUBLE |
| Narrow type | ❌ No | e.g., LONG → INT not allowed |

**Key insight — column IDs:**

Iceberg tracks columns by a **unique integer ID**, not by name. Renaming a column doesn't break existing data files — the engine maps the new name to the same column ID.

```sql
ALTER TABLE events ADD COLUMN user_country STRING;
ALTER TABLE events RENAME COLUMN user_id TO customer_id;  -- safe, tracked by ID
ALTER TABLE events ALTER COLUMN revenue TYPE DOUBLE;       -- widening, safe
```

---

## 9. Small File Problem

**Q: How does Iceberg handle the small file problem? What compaction strategies are available?**

**A:** Small files are common in streaming/incremental pipelines and degrade read performance significantly.

**Iceberg compaction via `rewrite_data_files`:**

```sql
-- Bin-pack strategy: merge small files into target size
CALL catalog.system.rewrite_data_files(
  table => 'db.events',
  strategy => 'binpack',
  options => map(
    'target-file-size-bytes', '134217728',  -- 128MB
    'min-input-files', '5'
  )
);

-- Sort strategy: rewrite + sort by column for better data skipping
CALL catalog.system.rewrite_data_files(
  table => 'db.events',
  strategy => 'sort',
  sort_order => 'user_id ASC NULLS LAST'
);
```

**Rewrite manifests** (metadata compaction):
```sql
CALL catalog.system.rewrite_manifests('db.events');
```

Too many manifest files slow down query planning — this consolidates them.

**Automated compaction options:**
- **AWS Glue** — native Iceberg compaction job.
- **Apache Spark** — schedule as a nightly Spark job via Airflow/Step Functions.
- **Amazon EMR** — auto-compaction support for Iceberg tables.

---

## 10. Iceberg Catalogs

**Q: What catalog options exist for Iceberg? What makes Nessie unique?**

**A:** The catalog tracks the **current metadata pointer** for each table.

| Catalog | Backend | Best for |
|---|---|---|
| **Hive Metastore** | RDBMS (MySQL/Postgres) | Existing Hive ecosystems |
| **AWS Glue** | Glue Data Catalog | AWS-native stacks |
| **Nessie** | Git-like versioning | Data-as-code, branching |
| **REST Catalog** | HTTP server | Multi-engine, vendor-neutral |
| **JDBC Catalog** | Any JDBC DB | Simple self-managed setups |
| **Hadoop Catalog** | HDFS/S3 (file-based) | Testing only — no concurrency support |

**Nessie** adds Git-like branching to Iceberg:

```bash
# Create a feature branch
nessie branch feature/new-pipeline

# Write data to the branch — isolated from main
spark.sql("INSERT INTO branch.feature.events ...")

# Merge branch to main after validation
nessie merge feature/new-pipeline --into main
```

This enables **zero-risk ETL experimentation** — test pipeline changes on a branch before promoting to production.

---

## 11. Iceberg vs. Delta Lake vs. Apache Hudi

**Q: How does Iceberg compare to Delta Lake and Hudi? When would you choose each?**

**A:**

| Feature | Iceberg | Delta Lake | Hudi |
|---|---|---|---|
| Origin | Netflix | Databricks | Uber |
| Open standard | ✅ Fully open | Partially (Linux Foundation) | ✅ Open |
| Engine support | Spark, Flink, Trino, Athena, Hive | Best on Spark/Databricks | Spark, Flink |
| Schema evolution | ✅ Best-in-class | ✅ Good | ✅ Good |
| Partition evolution | ✅ Yes | ❌ No | ❌ No |
| Hidden partitioning | ✅ Yes | ❌ No | ❌ No |
| Time travel | ✅ Yes | ✅ Yes | ✅ Yes |
| Row-level deletes | ✅ CoW + MoR | ✅ CoW + MoR | ✅ CoW + MoR |
| Streaming / CDC | ✅ Good | ✅ Good | ✅ Best (designed for CDC) |
| AWS native support | ✅ Athena, Glue, EMR | ✅ Athena, Glue | ✅ Athena, Glue |
| Branching | ✅ Via Nessie | ✅ Delta tables | ❌ No |

**When to choose Iceberg:**
- Multi-engine environments (Trino + Spark + Flink).
- Need partition evolution without data rewrites.
- AWS-native stack with Athena and Glue.

**When to choose Delta Lake:**
- Fully on Databricks with Delta Live Tables or Unity Catalog.

**When to choose Hudi:**
- Heavy CDC or streaming upsert workloads.
- Need record-level indexing for fast upserts.

---

## 12. Design Question: Streaming CDC Pipeline into Iceberg

**Q: Design a CDC pipeline from PostgreSQL into an Iceberg table on S3.**

**A:**

**Architecture:**

```
PostgreSQL (WAL)
    → Debezium (CDC connector)
    → Kafka (MSK)
    → Flink (stream processor)
    → Iceberg table on S3 (MoR mode)
    → Athena / Trino (queries)
```

**Key design decisions:**

1. **Use MoR (Merge-on-Read)** — CDC generates many small updates; MoR avoids constant file rewrites.

2. **Flink Iceberg sink handles upserts natively:**
   ```java
   FlinkSink.forRowData(dataStream)
       .tableLoader(tableLoader)
       .upsert(true)
       .equalityFieldColumns(List.of("primary_key_col"))
       .build();
   ```

3. **Nightly compaction job** — merge delete files and small data files into clean Parquet files using Spark.

4. **Schema evolution** — when PostgreSQL schema changes, Debezium emits schema change events. Flink detects the new schema and Iceberg's `ADD COLUMN` handles it safely with no downtime.

5. **Exactly-once delivery** — Flink checkpointing + Iceberg's two-phase commit ensures no duplicates even on Flink task failure.

---

## 13. Iceberg Write and Read Paths

**Q: Walk me through the full write path and read path in an Iceberg table.**

**A:**

**Write path:**

1. Writer generates new **data files** (Parquet/ORC) and writes them to the object store.
2. Writer creates a new **manifest file** listing those data files with column-level statistics.
3. Writer creates a new **manifest list** referencing the new manifest file (plus existing ones).
4. Writer creates a new **metadata.json** with a new snapshot pointing to the manifest list.
5. Writer performs an **atomic CAS** on the catalog to update the current metadata pointer.

**Read path:**

1. Query engine reads the **catalog** to get the current `metadata.json` location.
2. Engine reads `metadata.json` to find the **current snapshot** and its manifest list.
3. Engine reads the **manifest list** — filters out manifests whose partition ranges don't match the query predicates (**partition pruning**).
4. Engine reads the relevant **manifest files** — filters out data files whose column statistics (min/max) don't match predicates (**data skipping**).
5. Engine reads only the matching **data files** — applies any remaining row-level filters.

This layered pruning means a query touching 1% of data may only open 1% of files.

---

## 14. Performance Tuning

**Q: What are the main levers for tuning Iceberg query performance?**

**A:**

1. **Sorting data files** — sort by commonly filtered columns so min/max stats are tight and data skipping is effective:
   ```sql
   ALTER TABLE events WRITE ORDERED BY (user_id, event_time);
   ```

2. **Target file size** — keep data files in the 128MB–512MB range. Too small → many file opens; too large → wasted reads.

3. **Partition granularity** — match partition granularity to query patterns. Daily partitions for daily queries; hourly for near-real-time.

4. **Z-ordering / space-filling curves** — co-locate related rows across multiple dimensions:
   ```sql
   CALL catalog.system.rewrite_data_files(
     table => 'db.events',
     strategy => 'sort',
     sort_order => 'zorder(user_id, event_date)'
   );
   ```

5. **Manifest compaction** — too many manifest files slow down query planning. Run `rewrite_manifests` regularly.

6. **Column statistics** — ensure column-level min/max stats are present in manifest files. Iceberg writes these automatically for Parquet; verify stats are not being suppressed.

7. **Bloom filters** — enable Parquet bloom filters on high-cardinality equality-filter columns (e.g., `event_id`, `user_id`) for fast row-level lookups.

---

## 15. Maintenance Operations

**Q: What routine maintenance operations does an Iceberg table require?**

**A:**

| Operation | Purpose | Command |
|---|---|---|
| `expire_snapshots` | Remove old snapshots and orphaned data files to reduce storage cost | `CALL system.expire_snapshots(...)` |
| `rewrite_data_files` | Compact small files, sort data for better skipping | `CALL system.rewrite_data_files(...)` |
| `rewrite_manifests` | Consolidate many small manifest files to speed up planning | `CALL system.rewrite_manifests(...)` |
| `remove_orphan_files` | Delete data files not referenced by any snapshot (e.g., from failed writes) | `CALL system.remove_orphan_files(...)` |

**Recommended maintenance schedule:**

```
Hourly   → rewrite_data_files (for streaming tables with MoR)
Daily    → expire_snapshots (retain last 7 days)
Daily    → rewrite_manifests
Weekly   → remove_orphan_files
```

**Example — expire snapshots:**
```sql
CALL catalog.system.expire_snapshots(
  table => 'db.events',
  older_than => TIMESTAMP '2024-01-22 00:00:00',
  retain_last => 7
);
```

**Example — remove orphan files:**
```sql
CALL catalog.system.remove_orphan_files(
  table => 'db.events',
  older_than => TIMESTAMP '2024-01-20 00:00:00'
);
```

---

*Want deeper coverage of Iceberg with AWS Athena, Flink internals, or Iceberg REST catalog? Let me know!*