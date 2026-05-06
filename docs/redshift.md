# AWS Redshift — SWE III Data Engineering Interview Q&A
### Comprehensive Interview Preparation Guide

---

> **Coverage:** 40 questions across 8 categories — Architecture, Distribution & Sort Keys, Performance & Query Optimization, Data Loading & Unloading, Maintenance & Operations, Security & Compliance, Advanced Features, and System Design Scenarios.

---

## Table of Contents

1. [Architecture & Core Concepts](#1-architecture--core-concepts)
2. [Distribution & Sort Keys](#2-distribution--sort-keys)
3. [Performance & Query Optimization](#3-performance--query-optimization)
4. [Data Loading & Unloading](#4-data-loading--unloading)
5. [Maintenance & Operations](#5-maintenance--operations)
6. [Security & Compliance](#6-security--compliance)
7. [Advanced Features](#7-advanced-features)
8. [System Design Scenarios](#8-system-design-scenarios)
9. [SWE III Readiness Guide](#9-swe-iii-readiness-guide)

---

## 1. Architecture & Core Concepts

---

### Q1. What is Amazon Redshift and how does it differ from a traditional RDBMS?

**Answer:**

Amazon Redshift is a fully managed, petabyte-scale cloud data warehouse optimized for OLAP (analytical) workloads.

| Dimension | Traditional RDBMS | Amazon Redshift |
|---|---|---|
| Storage model | Row-based | Columnar |
| Processing | Single-node | MPP (Massively Parallel Processing) |
| Optimized for | OLTP (many small transactions) | OLAP (few large analytical queries) |
| Indexing | B-tree indexes | Zone maps + sort keys |
| Scale | Vertical | Horizontal (add nodes) |
| Joins | Nested loop, hash | Hash join (MPP-distributed) |
| Updates | Efficient in-place | Expensive (mark-delete + insert) |
| Workloads | Concurrent small reads/writes | Sequential large reads/aggregations |

**Key internals:**
- Columnar storage means only queried columns are read from disk — massive I/O savings for analytics
- MPP distributes data and query execution across compute nodes
- Data is compressed per-column using encoding specific to the data type

> **Interview tip:** The two foundational differentiators are columnar storage and MPP. Almost every follow-up question on Redshift performance traces back to these two concepts.

---

### Q2. Explain Redshift's architecture — Leader Node vs Compute Nodes vs Slices.

**Answer:**

```
Client
  │
  ▼
Leader Node
  │ (develops execution plan, coordinates, aggregates results)
  ├── Compute Node 1 ──► Slice 0 | Slice 1
  ├── Compute Node 2 ──► Slice 2 | Slice 3
  └── Compute Node N ──► Slice N | Slice N+1
```

**Leader Node:**
- Receives SQL from clients (JDBC/ODBC)
- Parses queries and develops parallel execution plans
- Distributes compiled query code to compute nodes
- Aggregates intermediate results from compute nodes
- Returns final result to client
- Does NOT store user data
- Not directly SSH-accessible in large clusters

**Compute Nodes:**
- Store actual data on local disk (DS2) or S3-backed managed storage (RA3)
- Execute query steps in parallel
- Communicate with each other for data redistribution (joins/aggregations)
- Each node is divided into **slices**

**Slices:**
- The actual unit of parallel processing — each slice has its own memory and CPU
- Number of slices per node depends on node type (e.g., ra3.4xlarge = 4 slices per node)
- Data is distributed across slices, not across nodes directly
- Every table is split across all slices in the cluster

> **Interview tip:** The distinction between nodes and slices matters for distribution key questions. Data is distributed at the slice level. A 2-node cluster with 4 slices per node has 8 slices total — 8-way parallelism.

---

### Q3. What are the Redshift node types and when would you choose each?

**Answer:**

| Node Type | Storage | Use Case |
|---|---|---|
| **RA3** | S3-backed (Redshift Managed Storage) | Recommended for most new workloads — compute and storage scale independently |
| **DS2** | Local HDD | Legacy; tightly couples compute and storage |
| **DC2** | Local SSD | Low-latency, compute-intensive workloads; smaller datasets |

**RA3 deep-dive (recommended default):**
- Decouples compute from storage — scale one without the other
- Uses local SSD as hot cache, S3 for persistent storage
- Enables cross-AZ data sharing
- Faster resize operations (no data migration for scale-up)
- Supports Redshift Managed Storage (RMS) — automatic data tiering
- Sub-types: `ra3.xlplus`, `ra3.4xlarge`, `ra3.16xlarge`

**When to use DC2:**
- Small datasets that fit entirely in SSD
- Latency-critical dashboards
- Cost-sensitive workloads with predictable, small data volumes

> **Interview tip:** RA3 is the right answer for almost any new workload. The key phrase: *"RA3 decouples compute and storage — you scale each independently, which is the fundamental cloud elasticity advantage over DS2."*

---

### Q4. What is the Redshift scheduler loop and how does WLM (Workload Management) fit in?

**Answer:**

Without WLM, all queries compete for the same resources. WLM lets you define **query queues** with dedicated memory and concurrency limits.

**WLM modes:**

| Mode | Description |
|---|---|
| **Auto WLM** (recommended) | Redshift dynamically adjusts concurrency and memory per queue based on available resources |
| **Manual WLM** | You configure fixed concurrency slots and memory % per queue |

**Queue routing:**

```sql
-- Route queries to specific queues via query groups
SET query_group TO 'etl';        -- routes to ETL queue
SET query_group TO 'reporting';  -- routes to reporting queue

-- Or via user groups — users in 'etl_users' group auto-route to ETL queue
```

**Short Query Acceleration (SQA):**
- Automatically routes short-running queries (<1-2 min) to a dedicated internal queue
- Prevents short BI queries from waiting behind long ETL queries
- Enable with: `enable_short_query_acceleration = true`

**Concurrency Scaling:**
- Automatically adds transient read clusters during peak load
- Charged per-second only when active
- Configured per queue: `concurrency_scaling = auto`

**Key WLM design principles:**
- Separate ETL queues (high memory, low concurrency) from BI queues (low memory, high concurrency)
- Allocate memory by workload profile — ETL needs big sort/hash buffers
- Use query monitoring rules (QMR) to auto-cancel runaway queries

```sql
-- Query Monitoring Rule: cancel queries using >1GB temp space for >5 minutes
-- (configured in WLM, not SQL — shown as concept)
-- Rule: if query_cpu_time > 300 AND query_blocks_read > 1000000 → abort
```

---

## 2. Distribution & Sort Keys

---

### Q5. What is a distribution style in Redshift and why does it matter?

**Answer:**

Distribution style determines how table rows are spread across slices. The goal is to **minimize data movement** (redistribution) during joins and aggregations — data movement is the most expensive operation in MPP.

| Style | How it works | Best for |
|---|---|---|
| `EVEN` | Round-robin across all slices | Default; avoids skew when no good key exists |
| `KEY` | Rows with same key value go to same slice | Tables frequently joined on that column |
| `ALL` | Full copy of table on every node | Small, frequently-joined dimension tables |
| `AUTO` | Redshift chooses based on table size | Let Redshift decide (starts as ALL for small, EVEN for large) |

**When to use each:**

```sql
-- EVEN: no clear join key, want balanced distribution
CREATE TABLE events (
    event_id BIGINT,
    event_type VARCHAR(50),
    event_ts TIMESTAMP
) DISTSTYLE EVEN;

-- KEY: this table is frequently joined to orders on customer_id
CREATE TABLE customers (
    customer_id BIGINT,
    name VARCHAR(100),
    region VARCHAR(20)
) DISTSTYLE KEY DISTKEY(customer_id);

-- ALL: small lookup/dimension table, joined everywhere
CREATE TABLE countries (
    country_code CHAR(2),
    country_name VARCHAR(100)
) DISTSTYLE ALL;
```

**The collocated join:** When two tables have the same DISTKEY on the join column, matching rows are already on the same slice — no data movement needed. This is the goal of KEY distribution.

> **Interview tip:** Classic scenario: *"Given orders (1B rows) and customers (10M rows) frequently joined on customer_id, what distribution would you choose?"* — KEY on `customer_id` for both tables → collocated join. `customers` could also be ALL if it's small enough (< a few hundred MB).

---

### Q6. What are sort keys in Redshift? What is the difference between compound and interleaved sort keys?

**Answer:**

Sort keys determine the physical storage order of data on disk. Redshift uses **zone maps** — metadata storing min/max values per 1MB disk block — to skip irrelevant blocks during scans. This is called **block-level pruning**.

**Why sort keys matter:**
```
Query: WHERE order_date BETWEEN '2024-01-01' AND '2024-01-31'
Without sort key: scan ALL blocks (no pruning possible)
With SORTKEY(order_date): skip all blocks where max < '2024-01-01' or min > '2024-01-31'
```

**Compound Sort Key:**
```sql
CREATE TABLE orders (
    order_id BIGINT,
    order_date DATE,
    customer_id BIGINT,
    region VARCHAR(20),
    amount DECIMAL(12,2)
)
COMPOUND SORTKEY(order_date, region, customer_id);

-- Effective for queries filtering on:
--   order_date alone              ✅ (prefix match)
--   order_date + region           ✅ (prefix match)
--   order_date + region + customer ✅ (full match)
--   region alone                  ❌ (no prefix — can't prune)
--   customer_id alone             ❌ (no prefix)
```

**Interleaved Sort Key:**
```sql
CREATE TABLE orders (...)
INTERLEAVED SORTKEY(order_date, region, customer_id);

-- Equal weight to all columns — effective for:
--   order_date alone              ✅
--   region alone                  ✅
--   customer_id alone             ✅
--   any combination               ✅

-- Trade-offs:
--   Higher VACUUM overhead (requires VACUUM REINDEX — very expensive)
--   Slower initial load
--   Degrades over time without regular REINDEX
--   Rarely worth the maintenance cost in practice
```

**Decision guide:**

| Scenario | Recommendation |
|---|---|
| Queries always filter on date | `COMPOUND SORTKEY(date_col)` |
| Queries filter on date + one other column | `COMPOUND SORTKEY(date_col, other_col)` |
| Queries filter on many combinations with no clear priority | Consider interleaved (but measure maintenance cost) |
| High-churn table with frequent inserts | Compound — VACUUM REINDEX for interleaved is too expensive |

> **Interview tip:** *"Interleaved sort keys everywhere"* is a common mistake. Compound is almost always better and far cheaper to maintain. Interleaved sort keys require `VACUUM REINDEX` which can take hours on large tables. The typical recommendation: use compound sort keys unless you have strong benchmarked evidence that interleaved provides meaningful improvement.

---

### Q7. What is data skew in Redshift and how do you diagnose and fix it?

**Answer:**

**Skew** occurs when data is unevenly distributed across slices — some slices process much more data than others, creating a bottleneck since the slowest slice determines query completion time.

**Two types:**

| Type | Cause | Symptom |
|---|---|---|
| Storage skew | Bad DISTKEY (low cardinality or hot key) | Some slices store 10x more data than others |
| Compute skew | Aggregation or join hot key (e.g., many NULLs, one dominant value) | Query step takes 10x longer on one slice |

**Diagnosing storage skew:**

```sql
-- Check row distribution across slices
SELECT slice, COUNT(*) as row_count
FROM stv_tbl_perm
WHERE name = 'your_table'
GROUP BY slice
ORDER BY slice;

-- Check via SVV_TABLE_INFO (simpler)
SELECT "table", skew_rows, skew_sortkey1
FROM svv_table_info
WHERE "table" = 'your_table';
-- skew_rows > 1.0 indicates skew (ratio of max to avg rows per slice)
```

**Diagnosing compute skew:**

```sql
-- Check slice-level execution in a query
SELECT query, slice, step, rows, elapsed
FROM svl_query_report
WHERE query = <query_id>
ORDER BY step, slice;
-- Look for slices where elapsed >> average
```

**Fixes:**

| Problem | Fix |
|---|---|
| Low-cardinality DISTKEY | Switch to EVEN or choose a higher-cardinality column |
| NULL-heavy join column | Add surrogate non-null key; avoid using nullable columns as DISTKEY |
| Hot key (one value dominates) | Use EVEN distribution + broadcast small table with ALL |
| Compute skew on aggregation | Pre-aggregate to reduce hot key dominance; use two-phase aggregation |

---

### Q8. How do you choose the right DISTKEY for a table?

**Answer:**

A good DISTKEY satisfies three criteria:

1. **High cardinality** — many distinct values so rows spread evenly across slices
2. **Frequent join column** — rows from both tables land on the same slice (collocated join)
3. **Not nullable** — NULL values all go to one slice, causing skew

**Decision framework:**

```
Step 1: Identify the most common join pattern for this table
Step 2: Is the join column high-cardinality? (>= number of slices)
  YES → Use that column as DISTKEY
  NO  → Check if a child column is high-cardinality
        If no good key exists → EVEN

Step 3: Verify no skew:
  SELECT COUNT(*), slice FROM stv_tbl_perm WHERE name='tbl' GROUP BY slice;
```

**Practical example — star schema:**

```sql
-- Fact table: orders (1B rows) — DISTKEY on foreign key used in most joins
CREATE TABLE fact_orders (
    order_id      BIGINT,
    customer_id   BIGINT,      -- most common join column → DISTKEY
    product_id    BIGINT,
    order_date    DATE,
    amount        DECIMAL(12,2)
)
DISTSTYLE KEY
DISTKEY(customer_id)
COMPOUND SORTKEY(order_date);

-- Dimension: customers — same DISTKEY for collocated join
CREATE TABLE dim_customers (
    customer_id   BIGINT,
    name          VARCHAR(200),
    region        VARCHAR(50)
)
DISTSTYLE KEY
DISTKEY(customer_id);

-- Small dimension: products — ALL for broadcast join
CREATE TABLE dim_products (
    product_id    BIGINT,
    product_name  VARCHAR(200),
    category      VARCHAR(100)
)
DISTSTYLE ALL;
```

---

## 3. Performance & Query Optimization

---

### Q9. How do you analyze a Redshift query execution plan?

**Answer:**

Use `EXPLAIN` to get the execution plan without running the query.

```sql
EXPLAIN
SELECT c.region, SUM(o.amount)
FROM fact_orders o
JOIN dim_customers c ON o.customer_id = c.customer_id
WHERE o.order_date >= '2024-01-01'
GROUP BY c.region;
```

**Key operators to understand:**

| Operator | Meaning |
|---|---|
| `XN Seq Scan` | Full sequential scan on a table |
| `XN Hash` | Build hash table for hash join |
| `XN Hash Join` | Hash join between two datasets |
| `XN Nested Loop` | Nested loop join — **avoid this, very expensive** |
| `XN Sort` | Sort operation |
| `XN Aggregate` | Aggregation |
| `XN Limit` | LIMIT clause |

**Data redistribution labels (most important for tuning):**

| Label | Meaning | Cost |
|---|---|---|
| `DS_DIST_NONE` | No redistribution — data already collocated | Free ✅ |
| `DS_BCAST_INNER` | Small inner table broadcast to all slices | Low ✅ |
| `DS_DIST_INNER` | Inner table redistributed by join key | Medium ⚠️ |
| `DS_DIST_BOTH` | Both tables redistributed | Expensive ❌ |
| `DS_DIST_ALL_INNER` | ALL-distributed table on inner side | Low ✅ |

**Reading a plan:**

```
XN Aggregate  (cost=...)
  -> XN Hash Join DS_DIST_NONE   <- ✅ collocated join, no movement
       Hash Cond: (o.customer_id = c.customer_id)
       -> XN Seq Scan on fact_orders  (filter: order_date >= '2024-01-01')
       -> XN Hash
            -> XN Seq Scan on dim_customers

-- DS_DIST_NONE means DISTKEY on customer_id for both tables is working correctly
```

> **Interview tip:** Being able to read `EXPLAIN` output and explain why `DS_DIST_BOTH` happens (and how to fix it via matching DISTKEYs) is a strong differentiator at SWE III level.

---

### Q10. What are the common causes of slow Redshift queries and how do you diagnose each?

**Answer:**

**Diagnostic starting point:**

```sql
-- Find slow queries in the last 24 hours
SELECT query, trim(querytxt) as sql,
       starttime, endtime,
       datediff(seconds, starttime, endtime) as duration_sec
FROM stl_query
WHERE starttime >= dateadd(hour, -24, GETDATE())
  AND aborted = 0
ORDER BY duration_sec DESC
LIMIT 20;
```

**Problem → Diagnosis → Fix:**

| Problem | Diagnosis | Fix |
|---|---|---|
| Full table scan (no pruning) | `EXPLAIN` shows filter on non-sort-key column | Add SORTKEY matching WHERE clause |
| Data redistribution | `EXPLAIN` shows `DS_DIST_BOTH` or `DS_DIST_INNER` | Align DISTKEY between joined tables |
| Storage skew | `svv_table_info.skew_rows > 1.0` | Change DISTKEY to higher-cardinality column |
| Unsorted data (zone maps ineffective) | `svv_table_info.pct_unsorted` high | Run `VACUUM SORT ONLY` |
| Stale statistics | Query plan choosing wrong join order | Run `ANALYZE` |
| Disk spill | `svl_query_summary.is_diskbased = 't'` | Increase WLM memory for queue; optimize query |
| Lock contention | `stl_tr_conflict` / `svv_transactions` | Identify and terminate blocking session |
| Nested loop join | `EXPLAIN` shows `XN Nested Loop` | Add explicit join conditions; avoid cross joins |

**Disk spill diagnosis:**

```sql
-- Find queries that spilled to disk
SELECT query, step, rows, workmem, label, is_diskbased
FROM svl_query_summary
WHERE is_diskbased = 't'
  AND query = <your_query_id>
ORDER BY step;
```

---

### Q11. How does columnar compression work in Redshift and how do you choose encoding?

**Answer:**

Redshift stores data column-by-column. Each column can have its own compression encoding, chosen based on data type and cardinality. Good encoding = less I/O = faster queries + lower storage cost.

**Encoding types:**

| Encoding | Best for | Notes |
|---|---|---|
| `RAW` | Any | No compression — avoid unless column is rarely scanned |
| `AZ64` | Numeric types, dates | Redshift's proprietary encoding — best for INT, BIGINT, DATE, TIMESTAMP |
| `ZSTD` | VARCHAR, general purpose | High compression ratio, good for text columns |
| `LZO` | Long VARCHAR | Fast decompression; good for longer strings |
| `BYTEDICT` | Low-cardinality columns | status, region, category — stores dictionary of unique values |
| `RUNLENGTH` | Repeating sorted values | Consecutive identical values — encode as value + count |
| `DELTA` | Sorted integer/date sequences | Stores differences between consecutive values |
| `DELTA32K` | Wider integer deltas | For larger delta ranges |

**Auto-select encoding:**

```sql
-- Let Redshift recommend encoding for an existing table
ANALYZE COMPRESSION your_table;

-- Output:
-- Column      | Encoding | Est_reduction_pct
-- order_id    | az64     | 45.23
-- status      | bytedict | 78.91
-- order_date  | az64     | 42.10
-- amount      | az64     | 38.55
-- description | zstd     | 65.30
```

**Encoding in CREATE TABLE:**

```sql
CREATE TABLE orders (
    order_id    BIGINT   ENCODE AZ64,
    status      VARCHAR  ENCODE BYTEDICT,
    order_date  DATE     ENCODE AZ64,
    amount      DECIMAL  ENCODE AZ64,
    description VARCHAR  ENCODE ZSTD
);
```

> **Interview tip:** `AZ64` is Redshift's newest encoding and the default for numeric/date types since 2019. Knowing this shows you're current. `BYTEDICT` for low-cardinality strings (status, region, type) is almost always the right call.

---

### Q12. What is the difference between COPY and INSERT for loading data into Redshift?

**Answer:**

| Aspect | COPY | INSERT |
|---|---|---|
| Performance | Parallel — all compute nodes load simultaneously | Serial — single leader node process |
| Source | S3, DynamoDB, EMR, SSH | SQL result set, VALUES |
| Recommended for | Any bulk load | Small lookups, single rows |
| Compression support | Gzip, Snappy, Bzip2, Zstd | N/A |
| Format support | Parquet, ORC, JSON, CSV, Avro | SQL only |
| Encoding application | Auto-applies column encoding | Auto-applies column encoding |
| Manifest support | Yes (explicit file list) | N/A |

**COPY is always preferred for bulk loads.**

```sql
-- COPY from S3 — Parquet (recommended format)
COPY orders
FROM 's3://my-bucket/data/orders/2024/01/'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftS3Role'
FORMAT AS PARQUET;

-- COPY from S3 — CSV with options
COPY orders (order_id, customer_id, amount, order_date)
FROM 's3://my-bucket/data/orders.csv'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftS3Role'
CSV
IGNOREHEADER 1
DATEFORMAT 'YYYY-MM-DD'
TRUNCATECOLUMNS
MAXERROR 10;

-- COPY with manifest (explicit file list — for precise control)
COPY orders
FROM 's3://my-bucket/manifests/orders_2024_01.manifest'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftS3Role'
MANIFEST
FORMAT AS PARQUET;
```

---

### Q13. How does Redshift handle JOINs internally, and what join strategies exist?

**Answer:**

Redshift uses **hash joins** as the primary join strategy for large tables.

**Join execution:**
1. Build phase: smaller table scanned, hash table built in memory (per slice)
2. Probe phase: larger table scanned, each row hashed and matched against hash table

**Data redistribution strategies before a join:**

```
Scenario 1: Both tables have matching DISTKEY on join column
→ DS_DIST_NONE — rows already collocated, no movement needed ✅

Scenario 2: One table is DISTSTYLE ALL
→ DS_DIST_ALL_INNER — full copy on every node, no movement ✅

Scenario 3: One table is small enough to broadcast
→ DS_BCAST_INNER — small table sent to all nodes ✅

Scenario 4: No DISTKEY match
→ DS_DIST_INNER or DS_DIST_BOTH — expensive redistribution ❌
```

**Nested loop joins (avoid):**

Nested loop appears when Redshift can't use hash join — usually from missing join conditions or cross joins. Each row in outer table scanned against all rows in inner table: O(n×m) complexity.

```sql
-- This produces a cross join / nested loop — AVOID
SELECT * FROM orders, customers;  -- missing JOIN ON clause

-- Correct:
SELECT * FROM orders o
JOIN customers c ON o.customer_id = c.customer_id;
```

**Join reordering:** Redshift's optimizer reorders joins based on table statistics. Run `ANALYZE` regularly so the optimizer has accurate row counts and makes good decisions.

---

## 4. Data Loading & Unloading

---

### Q14. What are best practices for bulk loading data into Redshift efficiently?

**Answer:**

**1. Use COPY, not INSERT**

COPY leverages all compute nodes in parallel. INSERT processes serially on the leader node.

**2. Use Parquet format from S3**

Parquet is columnar — Redshift only reads the columns needed. Eliminates parsing overhead vs CSV.

```sql
COPY target_table
FROM 's3://bucket/path/'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftS3Role'
FORMAT AS PARQUET;
```

**3. Split files to match number of slices**

Each slice processes one file at a time. Optimal: number of files = multiple of total slices.
```
2 nodes × 4 slices = 8 slices → use 8 or 16 or 24 files
File size: 100MB–1GB per file
```

**4. Load into sort key order**

Pre-sort data by sort key before loading → Redshift stores it sorted → less VACUUM needed.

**5. Use staging table + swap pattern for large loads:**

```sql
-- Load into staging table (no constraints, no sort key)
CREATE TABLE orders_staging (LIKE orders);
COPY orders_staging FROM 's3://...' IAM_ROLE '...' FORMAT AS PARQUET;

-- Validate staging data
SELECT COUNT(*) FROM orders_staging;

-- Atomic swap — zero downtime
BEGIN;
ALTER TABLE orders RENAME TO orders_old;
ALTER TABLE orders_staging RENAME TO orders;
DROP TABLE orders_old;
COMMIT;
```

**6. Vacuum and analyze after large loads**

```sql
VACUUM orders;    -- reclaim space from deleted rows, re-sort
ANALYZE orders;   -- update statistics for query optimizer
```

---

### Q15. How does UNLOAD work in Redshift and when would you use it?

**Answer:**

`UNLOAD` exports query results to S3 in parallel — each slice writes its own file(s). The inverse of COPY.

```sql
-- Basic UNLOAD to S3 as Parquet (recommended)
UNLOAD ('SELECT * FROM orders WHERE order_date >= ''2024-01-01''')
TO 's3://my-bucket/exports/orders_2024/'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftS3Role'
FORMAT AS PARQUET
ALLOWOVERWRITE
PARALLEL ON;

-- UNLOAD with manifest (know exactly which files were written)
UNLOAD ('SELECT order_id, amount FROM orders')
TO 's3://my-bucket/exports/orders_slim/'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftS3Role'
FORMAT AS PARQUET
MANIFEST
PARALLEL ON;

-- Partition output by date (Hive-compatible partition paths)
UNLOAD ('SELECT *, TO_CHAR(order_date,''YYYY'') as year,
                  TO_CHAR(order_date,''MM'') as month FROM orders')
TO 's3://my-bucket/exports/orders/'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftS3Role'
FORMAT AS PARQUET
PARTITION BY (year, month);
-- Creates: s3://bucket/exports/orders/year=2024/month=01/part-00.parquet
```

**Use cases:**
- Export aggregated results to S3 for downstream consumers (Athena, EMR, ML)
- Data archival — offload cold data from Redshift to S3
- Creating snapshots for data sharing
- Feeding data into data lake / lakehouse layers

> **Interview tip:** The `PARTITION BY` option in UNLOAD creates Hive-compatible partition paths that Glue Crawlers and Athena can discover automatically — a common data lake integration pattern.

---

### Q16. What is the Redshift MERGE statement and how does it compare to the DELETE+INSERT pattern?

**Answer:**

Before native MERGE support (added in 2022), the standard Redshift upsert pattern was a staged DELETE+INSERT:

**Legacy DELETE+INSERT pattern:**

```sql
-- Step 1: Stage incoming data
CREATE TEMP TABLE orders_updates AS
SELECT * FROM staging_orders;

-- Step 2: Delete existing rows that will be updated
DELETE FROM orders
WHERE order_id IN (SELECT order_id FROM orders_updates);

-- Step 3: Insert all rows (new + updated)
INSERT INTO orders
SELECT * FROM orders_updates;

-- Step 4: Clean up
DROP TABLE orders_updates;
```

**Modern MERGE statement (Redshift 2022+):**

```sql
MERGE INTO orders
USING staging_orders AS src
ON orders.order_id = src.order_id
WHEN MATCHED THEN
    UPDATE SET
        amount = src.amount,
        status = src.status,
        updated_at = src.updated_at
WHEN NOT MATCHED THEN
    INSERT (order_id, customer_id, amount, status, order_date, updated_at)
    VALUES (src.order_id, src.customer_id, src.amount,
            src.status, src.order_date, src.updated_at);
```

**Why Redshift UPDATEs are expensive:**

Redshift does not do in-place updates. An UPDATE internally:
1. Marks the old row as deleted (ghost row)
2. Inserts a new row with updated values

This means `ghost rows` accumulate and require `VACUUM DELETE ONLY` to reclaim space. For high-frequency update workloads, the DELETE+INSERT or MERGE approach on staging tables is more efficient than row-by-row UPDATEs.

---

## 5. Maintenance & Operations

---

### Q17. What is VACUUM in Redshift and what are its variants?

**Answer:**

VACUUM reclaims space from deleted/updated rows (ghost rows) and re-sorts data that was inserted out of sort order.

**VACUUM variants:**

| Command | What it does | When to use |
|---|---|---|
| `VACUUM FULL` | Sort + reclaim deleted space | General maintenance; most common |
| `VACUUM SORT ONLY` | Re-sort unsorted rows; don't reclaim space | After large bulk loads when space isn't the concern |
| `VACUUM DELETE ONLY` | Reclaim space from deleted rows; don't sort | After large DELETE operations |
| `VACUUM REINDEX` | Rebuild interleaved sort key indexes | Required after significant inserts when using INTERLEAVED SORTKEY |

```sql
-- Full vacuum on a specific table
VACUUM FULL orders;

-- Vacuum with sort threshold — only if > 5% unsorted
VACUUM SORT ONLY orders TO 95 PERCENT;

-- Check how much unsorted data exists before vacuuming
SELECT "table", pct_unsorted, size, tbl_rows
FROM svv_table_info
WHERE "table" = 'orders';

-- Auto-vacuum: RA3 nodes have background auto-vacuum
-- Manual vacuum still recommended after large bulk operations
```

**Ghost row monitoring:**

```sql
-- Check tables with high ghost row ratio
SELECT "table",
       tbl_rows,
       estimated_visible_rows,
       tbl_rows - estimated_visible_rows AS ghost_rows,
       ROUND(100.0 * (tbl_rows - estimated_visible_rows) / NULLIF(tbl_rows,0), 2) AS ghost_pct
FROM svv_table_info
WHERE tbl_rows - estimated_visible_rows > 1000000
ORDER BY ghost_pct DESC;
```

---

### Q18. What is ANALYZE in Redshift and when should you run it?

**Answer:**

`ANALYZE` collects statistics about table data — row counts, min/max values, null counts, column cardinality — and writes them to the metadata store. The query optimizer uses these statistics to choose efficient execution plans (join order, join type, scan strategy).

**When stale statistics hurt:**
- Optimizer chooses nested loop instead of hash join (wrong row estimate)
- Optimizer chooses wrong table for broadcast (underestimates table size)
- Suboptimal sort order in multi-join queries

```sql
-- Analyze entire table
ANALYZE orders;

-- Analyze specific columns (faster for wide tables)
ANALYZE orders (order_date, customer_id, amount);

-- Analyze with predicate columns only (Redshift recommends this)
ANALYZE orders PREDICATE COLUMNS;

-- Check when a table was last analyzed
SELECT "table", stats_off, last_analyzed
FROM svv_table_info
WHERE "table" = 'orders';

-- stats_off > 10 indicates statistics are stale — run ANALYZE
```

**Auto-analyze:** Redshift runs automatic ANALYZE in the background for RA3 nodes. Still recommended to run manually after large loads.

---

### Q19. How do you monitor Redshift cluster health and query performance in production?

**Answer:**

**Key system views for monitoring:**

```sql
-- 1. Slow queries in last 24h
SELECT query, trim(querytxt) as sql,
       starttime,
       datediff(seconds, starttime, endtime) as duration_sec,
       aborted
FROM stl_query
WHERE starttime >= dateadd(hour, -24, GETDATE())
ORDER BY duration_sec DESC LIMIT 20;

-- 2. Currently running queries
SELECT pid, query, trim(querytxt) as sql,
       starttime, wlm_queue_name
FROM stv_recents
WHERE status = 'Running';

-- 3. Queries waiting in WLM queue
SELECT * FROM stv_wlm_query_state
WHERE queue_time > 30000;  -- waiting > 30 seconds

-- 4. Lock contention
SELECT a.txn_owner, a.relation, b.txn_owner as blocked_by,
       a.granted
FROM svv_transactions a
JOIN svv_transactions b ON a.relation = b.relation
WHERE a.granted = 'f';  -- false = waiting for lock

-- 5. Disk usage by table
SELECT "table", size, pct_used
FROM svv_table_info
ORDER BY size DESC LIMIT 20;

-- 6. Cluster disk usage overall
SELECT SUM(used)::FLOAT / SUM(capacity) * 100 AS pct_disk_used
FROM stv_partitions;
```

**CloudWatch metrics to alarm on:**

| Metric | Alarm threshold |
|---|---|
| `CPUUtilization` | > 80% sustained |
| `PercentageDiskSpaceUsed` | > 75% |
| `DatabaseConnections` | > 80% of max_connections |
| `QueryDuration` | p99 > SLA threshold |
| `WLMQueuedQueries` | > 0 for extended period |
| `MaintenanceMode` | = 1 (cluster in maintenance) |

---

### Q20. How do you resize a Redshift cluster with zero or minimal downtime?

**Answer:**

**Two resize approaches:**

| Approach | Downtime | How it works |
|---|---|---|
| Classic resize | 2–8+ hours downtime (read-only during resize) | Provision new cluster, copy all data, update endpoint |
| Elastic resize | 10–15 minutes (brief connection interruption only) | Add/remove nodes; data redistributed in background |

**Elastic resize (preferred):**
```sql
-- Via AWS Console, CLI, or SDK
aws redshift resize-cluster \
    --cluster-identifier my-cluster \
    --number-of-nodes 8 \
    --node-type ra3.4xlarge

-- Constraints:
-- Can only double or halve node count
-- Node type must stay the same
-- Some node types don't support elastic resize
```

**RA3 advantage:** Because RA3 separates compute from storage (data is in S3/RMS), adding nodes doesn't require physically moving data — only the hot cache is rebuilt. This makes RA3 elastic resize much faster than DS2.

**Snapshot + restore for major changes:**
```sql
-- Create snapshot, restore to new cluster with different config
-- Zero downtime on the old cluster
-- CNAME/endpoint swap after validation
```

---

## 6. Security & Compliance

---

### Q21. What are the security layers in Amazon Redshift?

**Answer:**

```
Network Security
  ├── VPC isolation (cluster in private subnet)
  ├── Security groups (inbound rules on port 5439)
  └── VPC endpoints for S3 (no traffic over public internet)

Authentication
  ├── Database users (username/password)
  ├── IAM authentication (temporary credentials, no password)
  └── Federated SSO (SAML via AD/Okta → IAM role → Redshift)

Authorization
  ├── Database-level GRANT/REVOKE
  ├── Schema-level permissions
  ├── Table/column-level permissions
  └── Row-level security (RLS policies — added 2022)

Encryption
  ├── At rest: AES-256 via AWS KMS (HSM optional)
  └── In transit: SSL/TLS (enforced via parameter group)

Audit & Compliance
  ├── STL_CONNECTION_LOG (all connection attempts)
  ├── STL_USERLOG (user changes)
  └── Redshift audit logging → S3
```

**Row-level security (RLS) — important for SWE III:**

```sql
-- Create RLS policy: users only see their own region's data
CREATE RLS POLICY region_policy
WITH (region VARCHAR)
USING (region = CURRENT_USER);

-- Attach policy to table
ATTACH RLS POLICY region_policy ON orders TO PUBLIC;

-- Now a user with region='APAC' only sees APAC orders
-- SELECT * FROM orders  →  automatically filtered to region='APAC'
```

**Column-level security:**

```sql
-- Revoke access to PII columns
REVOKE SELECT (ssn, credit_card, email)
ON TABLE customers
FROM analyst_role;

-- Grant access to non-PII columns only
GRANT SELECT (customer_id, name, region, created_at)
ON TABLE customers
TO analyst_role;
```

---

### Q22. How does IAM authentication work with Redshift?

**Answer:**

IAM authentication lets AWS principals connect to Redshift using temporary credentials — no password management required.

**Flow:**

```
AWS Principal (IAM user/role)
  │
  ├── Calls redshift:GetClusterCredentials (or redshift-serverless:GetCredentials)
  │   with IAM permissions
  │
  ├── AWS returns temporary DB username + password (valid 15min-1hr)
  │
  └── Connects to Redshift with temporary credentials
```

**IAM policy for GetClusterCredentials:**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "redshift:GetClusterCredentials",
      "redshift:CreateClusterUser",
      "redshift:JoinGroup"
    ],
    "Resource": [
      "arn:aws:redshift:ap-south-1:123456789:dbname:my-cluster/analytics",
      "arn:aws:redshift:ap-south-1:123456789:dbuser:my-cluster/${redshift:DbUser}"
    ]
  }]
}
```

**Python connection with IAM:**

```python
import boto3
import psycopg2

# Get temporary credentials
redshift = boto3.client('redshift', region_name='ap-south-1')
creds = redshift.get_cluster_credentials(
    ClusterIdentifier='my-cluster',
    DbName='analytics',
    DbUser='myiamuser',
    AutoCreate=True,        # create DB user if it doesn't exist
    DurationSeconds=3600
)

conn = psycopg2.connect(
    host='my-cluster.xxx.ap-south-1.redshift.amazonaws.com',
    port=5439,
    database='analytics',
    user=creds['DbUser'],
    password=creds['DbPassword'],
    sslmode='require'
)
```

---

## 7. Advanced Features

---

### Q23. What is Redshift Spectrum and when would you use it?

**Answer:**

Redshift Spectrum lets you query data directly in S3 (data lake) without loading it into Redshift. It uses an external table mechanism backed by the AWS Glue Data Catalog.

```
Redshift cluster
  │
  ├── Internal tables (data in Redshift managed storage)
  └── External tables via Spectrum
        └── S3 data lake (Parquet, ORC, CSV, JSON, Avro)
              └── Metadata in Glue Data Catalog
```

**Setup:**

```sql
-- Create external schema pointing to Glue catalog
CREATE EXTERNAL SCHEMA data_lake
FROM DATA CATALOG
DATABASE 'my_glue_database'
IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftSpectrumRole'
CREATE EXTERNAL DATABASE IF NOT EXISTS;

-- External table (defined in Glue, queried via Spectrum)
CREATE EXTERNAL TABLE data_lake.orders_raw (
    order_id    BIGINT,
    customer_id BIGINT,
    amount      DOUBLE,
    order_date  DATE
)
STORED AS PARQUET
LOCATION 's3://my-data-lake/raw/orders/'
TABLE PROPERTIES ('classification'='parquet');

-- Join Redshift internal table with S3 external table
SELECT r.region, SUM(ext.amount) as total_amount
FROM data_lake.orders_raw ext                   -- S3 via Spectrum
JOIN redshift_internal.dim_customers r          -- Redshift internal
  ON ext.customer_id = r.customer_id
WHERE ext.order_date >= '2024-01-01'
GROUP BY r.region;
```

**When to use Spectrum:**

| Use Case | Spectrum | Internal Redshift |
|---|---|---|
| Hot, frequently-queried data | ❌ | ✅ |
| Cold/historical data (years old) | ✅ | ❌ (expensive to store) |
| Ad-hoc queries on raw data | ✅ | ❌ |
| Data lake / lakehouse architecture | ✅ | — |
| Petabyte-scale data | ✅ | ❌ (too expensive) |
| Sub-second latency required | ❌ | ✅ |

**Cost note:** Spectrum charges per TB of S3 data scanned. Use Parquet + partitioning to minimize scans. A `WHERE order_date = '2024-01-01'` on partitioned Parquet scans only that partition → minimal cost.

---

### Q24. What is Redshift Data Sharing and how does it enable cross-account/cross-cluster access?

**Answer:**

Data Sharing allows a producer cluster to share live Redshift data with consumer clusters — without copying data, without ETL, in real time.

```
Producer Cluster (owns data)
  │
  ├── Creates DATASHARE
  ├── Adds schemas/tables to datashare
  └── Grants access to consumer AWS account
           │
           ▼
Consumer Cluster (reads data)
  ├── Creates external schema from datashare
  └── Queries producer's data directly (read-only)
```

**Producer side:**

```sql
-- Create datashare
CREATE DATASHARE sales_share;

-- Add objects to share
ALTER DATASHARE sales_share ADD SCHEMA public;
ALTER DATASHARE sales_share ADD TABLE public.orders;
ALTER DATASHARE sales_share ADD TABLE public.dim_customers;

-- Grant access to consumer account
GRANT USAGE ON DATASHARE sales_share
TO ACCOUNT '987654321098';  -- consumer AWS account ID
```

**Consumer side:**

```sql
-- Create database from datashare
CREATE DATABASE sales_db
FROM DATASHARE sales_share
OF ACCOUNT '123456789012'  -- producer account
NAMESPACE 'xxxxxx';         -- producer cluster namespace

-- Query shared data
SELECT * FROM sales_db.public.orders
WHERE order_date >= '2024-01-01';
```

**Use cases:**
- Shared analytics platform — central data team produces, business units consume
- Cross-account isolation — prod cluster shares with dev cluster (read-only)
- Redshift Serverless consumer reading from provisioned cluster
- Data marketplace patterns

---

### Q25. What is Redshift Serverless and how does it differ from provisioned Redshift?

**Answer:**

| Aspect | Provisioned Redshift | Redshift Serverless |
|---|---|---|
| Capacity | Fixed node type + count | Auto-scales RPUs (Redshift Processing Units) |
| Billing | Per node-hour (always on) | Per RPU-second (pay for actual compute) |
| Idle cost | Full cost even with no queries | Zero cost when idle |
| Startup latency | None (always running) | Cold start: 5–30 seconds |
| WLM | Manual WLM configuration | Automatic |
| Max RPU | N/A | Configurable (8–512 RPUs) |
| Best for | Steady, predictable workloads | Intermittent, variable, or dev/test workloads |

```python
import boto3

# Redshift Serverless connection
client = boto3.client('redshift-data', region_name='ap-south-1')

response = client.execute_statement(
    WorkgroupName='my-workgroup',   # instead of ClusterIdentifier
    Database='analytics',
    Sql='SELECT COUNT(*) FROM orders',
    WithEvent=True
)
```

**RPU scaling:** Redshift Serverless automatically scales RPUs between `base_capacity` and `max_capacity` based on query demand. More concurrent complex queries → more RPUs allocated automatically.

---

### Q26. What is Materialized Views in Redshift and how do they differ from regular views?

**Answer:**

| Aspect | Regular View | Materialized View |
|---|---|---|
| Storage | No — just SQL definition | Yes — stores query result on disk |
| Query time | Executes base query every time | Reads pre-computed result (fast) |
| Data freshness | Always current | May be stale until refreshed |
| Refresh | N/A | Manual or auto-refresh |
| Cost | Compute per query | Storage + compute at refresh |

```sql
-- Create materialized view: pre-aggregate daily revenue by region
CREATE MATERIALIZED VIEW daily_revenue_by_region
AUTO REFRESH YES
AS
SELECT
    order_date,
    region,
    COUNT(order_id)     AS order_count,
    SUM(amount)         AS total_revenue,
    AVG(amount)         AS avg_order_value
FROM orders o
JOIN dim_customers c ON o.customer_id = c.customer_id
GROUP BY order_date, region;

-- Query the materialized view (fast — reads pre-computed result)
SELECT * FROM daily_revenue_by_region
WHERE order_date >= '2024-01-01';

-- Manual refresh (if AUTO REFRESH NO)
REFRESH MATERIALIZED VIEW daily_revenue_by_region;

-- Check refresh status
SELECT mv_name, is_stale, last_refresh_time
FROM stv_mv_info;
```

**AUTO REFRESH:** Redshift automatically refreshes the MV when base tables are updated. Uses incremental refresh when possible (only re-computes changed partitions). Falls back to full refresh for complex queries.

**Use case:** Replace expensive dashboard queries that aggregate millions of rows with materialized views that are refreshed on schedule. BI tools query the MV instead of the base tables.

---

## 8. System Design Scenarios

---

### Q27. Design a Redshift data warehouse for a multi-tenant SaaS company with strict data isolation requirements.

**Answer:**

**Requirements:** Multiple customers, each must only see their own data. 100+ tenants, variable query patterns per tenant.

**Architecture:**

```
Option A: Schema per tenant (recommended for <100 tenants)
  analytics_db
    ├── tenant_acme/  (schema)
    │     ├── orders
    │     ├── customers
    │     └── events
    ├── tenant_globex/ (schema)
    │     ├── orders
    │     └── ...
    └── shared/ (common dimension tables)

Option B: Single schema + RLS (recommended for 100+ tenants)
  analytics_db
    └── public/
          ├── orders       (tenant_id column + RLS policy)
          ├── customers    (tenant_id column + RLS policy)
          └── events       (tenant_id column + RLS policy)
```

**Option B implementation (RLS-based, scalable):**

```sql
-- Add tenant_id to all tables
ALTER TABLE orders ADD COLUMN tenant_id VARCHAR(50);

-- Create RLS policy
CREATE RLS POLICY tenant_isolation
WITH (tenant_id VARCHAR)
USING (tenant_id = current_setting('app.tenant_id'));

-- Attach to all tenant tables
ATTACH RLS POLICY tenant_isolation ON orders TO PUBLIC;
ATTACH RLS POLICY tenant_isolation ON customers TO PUBLIC;

-- Per-tenant IAM role maps to Redshift user with tenant_id set
-- At connection time:
SET app.tenant_id = 'acme-corp';
-- Now: SELECT * FROM orders → only returns acme-corp rows
```

**Distribution strategy:**
- DISTKEY on `tenant_id` if queries are tenant-scoped (all tenant's data on same slices)
- EVEN if cross-tenant analytics are common (analytics team queries)

**WLM isolation:**
- Separate queue per tier (premium tenants get dedicated queue)
- QMR rules to limit per-tenant resource consumption

---

### Q28. How would you design an incremental ELT pipeline that loads from S3 into Redshift daily, handling schema changes and late-arriving data?

**Answer:**

**Pipeline architecture:**

```
S3 Landing Zone (raw data)
  └── Daily partition: s3://bucket/orders/year=2024/month=01/day=10/
          │
          ▼
Glue ETL Job (transform + validate)
          │
          ▼
S3 Processed Zone (Parquet, partitioned)
          │
          ▼
Redshift staging table
          │
          ├── Schema validation
          ├── Dedup
          └── MERGE into production table
```

**Schema change handling:**

```sql
-- Use CREATE TABLE LIKE for staging — inherits schema from production
CREATE TEMP TABLE orders_staging (LIKE orders);

-- After COPY into staging, validate schema compatibility
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'orders_staging'
EXCEPT
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'orders';
-- If this returns rows → schema mismatch → alert and abort

-- Add new non-nullable column with DEFAULT (backward compatible)
ALTER TABLE orders ADD COLUMN discount_pct DECIMAL(5,2) DEFAULT 0.00;
```

**Late-arriving data handling:**

```sql
-- Partitioned by event_date, not load_date
-- Late record for 2024-01-05 arriving on 2024-01-08:

-- Option 1: MERGE handles it — upserts on primary key
MERGE INTO orders
USING orders_staging src
ON orders.order_id = src.order_id
WHEN MATCHED THEN UPDATE SET ...
WHEN NOT MATCHED THEN INSERT ...;

-- Option 2: Dynamic partition overwrite — reload the affected partition
DELETE FROM orders WHERE order_date = '2024-01-05';
INSERT INTO orders SELECT * FROM orders_staging
WHERE order_date = '2024-01-05';
```

**Idempotency guarantee:**

```sql
-- Every pipeline run for a given date produces the same result
-- Key: always DELETE then INSERT for the target partition, never pure APPEND
BEGIN;
DELETE FROM orders WHERE order_date = '{{ ds }}';
INSERT INTO orders
SELECT * FROM orders_staging WHERE order_date = '{{ ds }}';
COMMIT;
```

---

### Q29. A query that used to run in 30 seconds now takes 15 minutes. Walk me through how you would debug this.

**Answer:**

**Systematic debugging approach:**

```sql
-- Step 1: Get the query ID
SELECT query, trim(querytxt), starttime, endtime,
       datediff(seconds, starttime, endtime) as duration_sec
FROM stl_query
WHERE trim(querytxt) LIKE '%orders%'
ORDER BY starttime DESC LIMIT 10;

-- Step 2: Check for data redistribution (most common cause of regression)
EXPLAIN <the slow query>;
-- Look for: DS_DIST_BOTH or DS_DIST_INNER that wasn't there before

-- Step 3: Check table statistics (stale stats → bad plan)
SELECT "table", stats_off, pct_unsorted, size
FROM svv_table_info
WHERE "table" IN ('orders', 'dim_customers');
-- stats_off > 10 or pct_unsorted > 20 → run ANALYZE and VACUUM

-- Step 4: Check for skew (new hot key due to data growth)
SELECT slice, COUNT(*) FROM stv_tbl_perm
WHERE name = 'orders' GROUP BY slice ORDER BY slice;

-- Step 5: Check if query spilled to disk
SELECT query, step, rows, workmem, label, is_diskbased
FROM svl_query_summary
WHERE query = <query_id>
ORDER BY step;

-- Step 6: Check for lock contention
SELECT * FROM stv_locks WHERE relation IN
  (SELECT oid FROM pg_class WHERE relname = 'orders');

-- Step 7: Check WLM queue — was the query queued for a long time?
SELECT query, queue_start_time, exec_start_time,
       datediff(seconds, queue_start_time, exec_start_time) as queue_wait_sec
FROM stl_wlm_query WHERE query = <query_id>;
```

**Common root causes and fixes:**

| Root cause | Fix |
|---|---|
| Table grew → full scan now expensive | Add/modify SORTKEY to enable pruning |
| DISTKEY chosen on column that became skewed | Change DISTKEY to higher-cardinality column |
| Statistics stale (table grew) | `ANALYZE orders;` |
| Unsorted data after bulk loads | `VACUUM SORT ONLY orders;` |
| Query spilling to disk | Increase WLM memory; optimize subqueries |
| Lock contention from concurrent writes | Review write patterns; use staging table approach |
| New join added without matching DISTKEY | Align DISTKEY between joined tables |

---

### Q30. How would you design a cost-optimized Redshift setup for a data engineering team with mixed workloads — heavy ETL at night, heavy BI queries during business hours?

**Answer:**

**Architecture:**

```
Production Cluster (RA3, always-on, right-sized for BI peak)
  ├── WLM Queue 1: ETL (10:00 PM – 6:00 AM)
  │     Memory: 60%, Concurrency: 3, Priority: High during off-hours
  └── WLM Queue 2: BI/Reporting (8:00 AM – 8:00 PM)
        Memory: 40%, Concurrency: 15, Concurrency Scaling: ON
        SQA: Enabled (short queries get fast lane)

Redshift Serverless Workgroup (dev/test/ad-hoc)
  ├── Zero idle cost
  ├── Max 64 RPUs (enough for ad-hoc)
  └── Accessible to analysts — no prod access
```

**WLM schedule configuration:**

```python
# Automated WLM switching via Lambda + CloudWatch Events
import boto3

def switch_wlm_to_etl_mode(event, context):
    """Called at 10 PM — prioritize ETL"""
    redshift = boto3.client('redshift')
    # Modify WLM parameter group: ETL queue gets 70% memory
    # (done via parameter group modification + cluster restart, or auto WLM)

def switch_wlm_to_bi_mode(event, context):
    """Called at 6 AM — prioritize BI"""
    # ETL queue gets 20% memory, BI queue gets 80%
```

**Cost optimizations:**

| Optimization | Saving |
|---|---|
| RA3 vs DC2 for variable workloads | Pay only for storage you use |
| Concurrency Scaling: ON for BI peak | Pay per-second for burst capacity, not always-on nodes |
| Redshift Serverless for dev/test | Zero idle cost (vs always-on dev cluster) |
| Spectrum for cold historical data | S3 is 20x cheaper than Redshift storage per GB |
| Compression (AZ64, BYTEDICT) | 30–70% storage reduction → fewer nodes needed |
| Materialized views for BI aggregations | Reduce compute for repeated dashboard queries |
| Short Query Acceleration | Short queries don't wait behind long ETL → better WLM utilization |

**Monitoring cost:**

```sql
-- Track query-level resource consumption
SELECT query, trim(querytxt) as sql,
       blocks_read, blocks_written,
       elapsed / 1000000 as elapsed_sec
FROM stl_query
WHERE starttime >= DATEADD(day, -7, GETDATE())
ORDER BY blocks_read DESC LIMIT 20;
-- High blocks_read = good candidate for sort key / compression optimization
```

---

## 9. SWE III Readiness Guide

---

### Is this content good for a SWE III Data Engineering interview?

**Yes — and it covers all the dimensions interviewers probe at senior level.**

### SWE III Redshift competency map

| Topic | Difficulty | SWE III relevance |
|---|---|---|
| Columnar storage + MPP fundamentals | Medium | ⭐⭐⭐ Always asked |
| Leader/Compute node + slices | Medium | ⭐⭐⭐ Always asked |
| Distribution styles (EVEN/KEY/ALL) | Medium-Hard | ⭐⭐⭐ Always asked |
| Sort keys (compound vs interleaved) | Medium-Hard | ⭐⭐⭐ Always asked |
| Skew diagnosis + fix | Hard | ⭐⭐⭐ Senior signal |
| EXPLAIN plan reading | Hard | ⭐⭐⭐ Strong differentiator |
| Compression encodings (AZ64, BYTEDICT) | Medium | ⭐⭐ Increasingly asked |
| COPY vs INSERT + bulk load patterns | Medium | ⭐⭐⭐ Always asked |
| VACUUM variants | Medium | ⭐⭐⭐ Always asked |
| ANALYZE + stale statistics | Medium | ⭐⭐ Good to know |
| WLM + SQA + Concurrency Scaling | Hard | ⭐⭐⭐ Always asked for senior |
| Row-level security | Medium | ⭐⭐ Increasingly relevant |
| IAM authentication | Medium | ⭐⭐⭐ AWS-specific must-know |
| Redshift Spectrum | Medium | ⭐⭐⭐ Very common |
| Data Sharing | Medium | ⭐⭐ Modern feature |
| Redshift Serverless | Medium | ⭐⭐ Increasingly asked |
| Materialized views | Medium | ⭐⭐ Good differentiator |
| MERGE statement | Medium | ⭐⭐⭐ Practical must-know |
| System design: multi-tenant | Hard | ⭐⭐⭐ Senior design signal |
| System design: ELT pipeline | Hard | ⭐⭐⭐ Core data engineering |
| Debugging slow queries | Hard | ⭐⭐⭐ Production experience signal |
| Cost optimization design | Hard | ⭐⭐⭐ Senior signal |

### The three answers that separate senior candidates

**1. Reading EXPLAIN output fluently**

Most candidates know that DISTKEY helps performance. Senior candidates can look at an EXPLAIN plan, spot `DS_DIST_BOTH`, explain *why* it's happening (mismatched DISTKEYs), and prescribe the fix. This shows real debugging experience.

**2. Connecting UPDATE behavior to VACUUM**

Knowing that Redshift UPDATEs are mark-delete + insert, that ghost rows accumulate, and that VACUUM reclaims space shows you understand the storage model internally — not just the SQL surface.

**3. WLM design for mixed workloads**

Designing separate queues for ETL vs BI, explaining SQA for short queries, and knowing when to enable Concurrency Scaling shows you've operated Redshift in a real multi-workload environment.

### Topics to study additionally

- **Redshift Federated Query** — query live data in RDS/Aurora without ETL
- **AQUA (Advanced Query Accelerator)** — hardware-accelerated cache for RA3
- **Redshift ML** — `CREATE MODEL` for in-database machine learning via SageMaker
- **dbt + Redshift** — incremental models, schema management, testing patterns
- **Cross-database queries** — query across multiple Redshift databases in one SQL statement

---

*Generated for SWE III Data Engineering interview preparation — AWS Redshift comprehensive guide.*
*Covers: Architecture, Distribution & Sort Keys, Performance, Data Loading, Maintenance, Security, Advanced Features, and System Design.*