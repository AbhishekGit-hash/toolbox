# AWS Data Engineering Interview Questions & Answers — SWE III Level

---

## Data Storage & Modeling

---

**Q1. You have a dataset in S3 partitioned by `year/month/day`. Queries frequently filter by a specific `user_id`. What are the trade-offs of re-partitioning by `user_id`, and how would you approach this without downtime?**

**A:**
- Use a **dual-write strategy** — write new data to both old and new partition schemes simultaneously during migration.
- Run a **Glue/EMR Spark job** to backfill historical data into the new `user_id/year/month` layout at a separate S3 prefix.
- Once backfill completes, **atomically update the Glue Data Catalog** to point to the new prefix.
- Keep the old partition path alive until all consumers are migrated.

**Trade-offs:**

| Factor | Time-based | user_id-based |
|---|---|---|
| User queries | Slow (full scan) | Fast (partition pruning) |
| Time-range queries | Fast | Slow |
| Data skew risk | Low | High (power users) |

**Skew mitigation:** Use a composite key like `user_id_bucket` (hash mod 256) if a few users generate disproportionate data.

---

**Q2. When would you choose Redshift Spectrum over Athena for querying S3 data? What are the cost and performance implications?**

**A:**

| Factor | Redshift Spectrum | Athena |
|---|---|---|
| Best for | Joining S3 data with Redshift tables | Ad-hoc serverless S3 queries |
| Compute | Uses Redshift cluster nodes | Fully serverless |
| Cost | Spectrum charges + cluster cost | $5/TB scanned |
| Performance | Better for complex joins with Redshift data | Better for isolated S3 queries |
| Concurrency | Limited by cluster WLM | High (serverless) |

- **Choose Spectrum** when you need to join large S3 datasets with existing Redshift tables.
- **Choose Athena** when teams need serverless ad-hoc exploration with no cluster to manage.

---

**Q3. Your Glue Data Catalog table gets a new column added upstream. How does this affect downstream Athena queries and Glue ETL jobs? How do you handle schema evolution gracefully?**

**A:**
- **Athena** picks up new columns automatically after `MSCK REPAIR TABLE` or with partition projection enabled.
- **Glue DynamicFrames** handle new columns gracefully — schema-on-read by nature.
- **Glue Spark DataFrames** with explicit schemas will **break** if new columns appear unexpectedly.

**Handling it gracefully:**
- Use `DynamicFrames` over raw Spark DataFrames for flexibility.
- Enable `UpdateBehavior = UPDATE_IN_DATABASE` in Glue crawlers for auto-catalog updates.
- For Redshift targets, run `ALTER TABLE ADD COLUMN` before loading.
- Use **AWS Glue Schema Registry** with compatibility modes (`BACKWARD`, `FORWARD`, `FULL`) to enforce contracts.
- Add a schema validation step at pipeline entry to detect changes early and alert rather than silently corrupt data.

---

## ETL / Pipeline Design

---

**Q4. Your AWS Glue PySpark job is running slowly on a 50GB dataset. Walk me through at least 3 levers you'd pull to optimize it.**

**A:**

1. **<mark>Push-down predicates** — read only relevant partitions</mark>:
   ```python
   glue_context.create_dynamic_frame.from_catalog(
       push_down_predicate="year='2024' and month='01'"
   )
   ```

2. **Convert to <mark>columnar format</mark>** — switch CSV/JSON sources to <mark>Parquet</mark> or ORC. Reduces I/O by 60–90% via column pruning and compression.

3. **<mark>Increase DPUs</mark> / enable auto-scaling** — use G.2X workers for memory-intensive jobs and set `--enable-auto-scaling`.

4. **Avoid unnecessary shuffles** — operations like <mark>`groupBy` trigger expensive shuffles</mark>. Use `repartition()` or `coalesce()` strategically.

5. **Enable <mark>Glue Job Bookmarks</mark>** — prevents reprocessing already-processed data on reruns, reducing total data scanned.

6. **Cache repeated DataFrames** — call <mark>`.cache()` on DataFrames used multiple times</mark> to avoid recomputation.

---

**Q5. How do you design an idempotent ETL pipeline on AWS — Lambda → Glue → Redshift? What happens if a step fails mid-way and retries?**

**A:**
- **Lambda → S3:** Derive S3 object keys from the source event ID (e.g., `s3://bucket/raw/event_id=abc123.json`). Rewriting the same key is safe.
- **S3 → Glue:** Use **Glue Job Bookmarks** to track processed files — retries only pick up unprocessed files.
- **Glue → Redshift:** Use <mark>`MERGE` (upsert)</mark> keyed on a natural business key instead of `INSERT`:
  ```sql
  MERGE INTO target USING staging
  ON target.event_id = staging.event_id
  WHEN MATCHED THEN UPDATE SET ...
  WHEN NOT MATCHED THEN INSERT ...
  ```
- **Step Functions:** Use <mark>idempotency tokens on Lambda invocations</mark> — same token on retry prevents double-execution.

---

**Q6. You're building a daily batch pipeline in Step Functions. How do you handle late-arriving data that arrives 2 days after the partition it belongs to?**

**A:**

1. **Reprocessable partitions** — store raw data by `arrival_time` but process output partitions by `event_time`. Late data triggers a rerun of the affected output partition.

2. **EventBridge re-trigger** — detect late S3 writes and re-trigger the Step Functions execution for the affected date partition.

3. **<mark>Watermarking</mark>** — track partition state (`OPEN`, `CLOSED`) in DynamoDB. Only <mark>finalize a partition after a configurable grace period</mark> (e.g., 3 days after partition date).

4. **Correction tables** — instead of mutating finalized partitions, write late data to a `corrections` table and union it in downstream views/queries.

---

## Streaming

---

**Q7. A system produces 50,000 events/sec with unpredictable spikes. Compare Kinesis Data Streams vs. MSK (Kafka). What factors drive your decision?**

**A:**

| Factor | Kinesis Data Streams | MSK (Kafka) |
|---|---|---|
| Management overhead | Fully managed | Managed but more ops |
| Throughput per shard | 1 MB/s in, 2 MB/s out | Configurable, much higher |
| Scaling | On-demand or manual shard split | Add brokers/partitions |
| Retention | 1–365 days | Configurable |
| Ecosystem | AWS-native (Lambda, Firehose) | Full Kafka ecosystem |
| Cost at scale | Moderate | Lower at high throughput |

- **Choose Kinesis On-Demand** for zero-ops scaling in an AWS-native stack.
- **Choose MSK** if you need Kafka Streams, ksqlDB, fine-grained consumer group control, or plan to grow beyond Kinesis cost-efficiency.

---

**Q8. You're consuming from Kinesis into a Lambda that writes to DynamoDB. How do you prevent duplicate records during retries?**

**A:**

1. **Conditional writes in DynamoDB** — fail silently if the record already exists:
   ```python
   table.put_item(
       Item={"event_id": event_id, ...},
       ConditionExpression="attribute_not_exists(event_id)"
   )
   ```

2. **Use Kinesis sequence number as the idempotency key** — same event always has the same sequence number, making it a safe DynamoDB primary key or upsert key.

3. **AWS Lambda Powertools Idempotency** — built-in decorator that stores request hashes in DynamoDB with a TTL, preventing duplicate processing at the Lambda level.

---

**Q9. Your Kinesis stream has hot shards because all events from one tenant share the same partition key. How do you fix this without losing data or ordering guarantees?**

**A:**

1. **Shard splitting** — split the hot shard into two via CLI:
   ```bash
   aws kinesis split-shard --stream-name my-stream \
     --shard-to-split shardId-000000000000 \
     --new-starting-hash-key 170141183460469231731687303715884105728
   ```
   The parent shard becomes read-only and drains safely before closing — no data loss.

2. **Key salting** — append a random suffix to spread load across shards:
   ```python
   partition_key = f"{tenant_id}_{random.randint(0, 9)}"
   ```
   Consumers must aggregate across all suffixes — adds complexity but eliminates hotspots.

3. **Ordering trade-off** — salting breaks strict per-tenant ordering. Accept ordering only within a shard, or use a single suffix per tenant session if ordering matters.

---

## Data Quality & Observability

---

**Q10. You need to enforce row-count thresholds, null checks, and referential integrity in a Glue pipeline. What tools or patterns would you use?**

**A:**

- **AWS Glue Data Quality (native)** — zero extra libraries, define rulesets in Glue Studio:
  ```
  Rules = [
    RowCount > 1000,
    IsComplete "user_id",
    Uniqueness "event_id" > 0.99
  ]
  ```

- **AWS Deequ** (Spark-native) — programmatic checks in PySpark:
  ```python
  check = Check(spark, "my_check")
      .hasSize(lambda x: x > 1000)
      .isComplete("user_id")
      .isUnique("event_id")
  ```

- **Great Expectations** — expressive checks with human-readable data docs UI. Integrates with Glue via Python shell jobs.

- **Pattern:** Run checks at *ingestion*, *transformation*, and *load* stages. Fail fast and route bad records to a dead-letter S3 prefix for inspection.

---

**Q11. How would you set up alerting for a Step Functions pipeline so on-call is paged if a stage takes more than 2x its p95 runtime?**

**A:**

1. **Emit custom CloudWatch metrics** from each Lambda/Glue step — duration, record count, error count.

2. **CloudWatch Alarms** — compute p95 baseline from last 30 days via Metric Math. Alarm triggers if current duration exceeds 2× p95.

3. **EventBridge + SNS** — Step Functions emits state change events to EventBridge. Route `FAILED` or `TIMED_OUT` events → SNS → PagerDuty/Slack.

4. **Execution audit trail** — store execution ARNs with timestamps in DynamoDB for custom dashboards and historical analysis.

5. **X-Ray tracing** — enable on Step Functions for distributed traces across Lambda and Glue steps to pinpoint latency sources.

---

## Cost & Performance

---

**Q12. A team's ad-hoc Athena queries are scanning entire tables and costing thousands per month. What changes would you recommend?**

**A:**

**Query-level fixes:**
- Use `SELECT col1, col2` instead of `SELECT *` — Athena charges per byte scanned, so column pruning saves money.
- Always filter on partition columns in `WHERE` clauses.
- Use `LIMIT` during exploration.

**Architectural fixes:**
- **Convert to Parquet/ORC** — reduces bytes scanned by 60–90%.
- **Partition data** by the most common filter dimensions.
- **Compress data** with Snappy or ZSTD.
- **Use partition projection** — avoids expensive Glue catalog lookups on high-partition tables.

**Governance fixes:**
- Set **Athena workgroup byte scan limits** per query:
  ```
  BytesScannedCutoffPerQuery: 10GB
  ```
- Tag workgroups by team and use AWS Cost Explorer for team-level chargebacks.

---

**Q13. Multiple teams share a Redshift cluster. Heavy ETL jobs are starving BI dashboard queries. How do you fix this with WLM?**

**A:**

**Manual WLM — separate queues:**
```
Queue 1 — BI Dashboards:
  Concurrency: 15 | Memory: 30% | Timeout: 60s | Group: bi_users

Queue 2 — ETL Jobs:
  Concurrency: 3  | Memory: 60% | Timeout: none | Group: etl_service

Queue 3 — Default:
  Concurrency: 5  | Memory: 10%
```

- Enable **Short Query Acceleration (SQA)** to fast-lane queries estimated to finish in under 20 seconds.
- Enable **Automatic WLM** to let Redshift dynamically manage memory and concurrency — often outperforms manual tuning.
- Use **Query Monitoring Rules (QMR)** to kill or hop runaway queries that exceed row/time thresholds.

---

## Design & Debugging

---

**Q14. Design an end-to-end pipeline that ingests clickstream data, stores raw data, transforms it hourly, and serves aggregated metrics to a dashboard.**

**A:**

```
API Gateway → Kinesis Data Streams → Lambda (validation)
    → S3 (raw/bronze) → Glue (hourly ETL) → S3 (processed/silver)
    → Athena / Redshift Spectrum → QuickSight
```

| Service | Role | Why |
|---|---|---|
| API Gateway | Ingestion endpoint | Managed, auto-scales, auth via Cognito |
| Kinesis Data Streams | Event buffer | Durable, ordered, replayable |
| Lambda | Validation + fan-out | Lightweight per-event checks, DLQ to SQS |
| S3 (raw) | Bronze layer | Immutable, cheap, queryable |
| Glue | Transformation | Serverless Spark, Glue Catalog integration |
| S3 (processed) | Silver layer | Parquet, partitioned by event_date |
| Athena | Serving layer | Serverless SQL over S3 |
| QuickSight | Dashboard | Native AWS BI, SPICE for fast aggregations |
| Step Functions | Orchestration | Retry logic, state management |
| CloudWatch + SNS | Monitoring | Alarms, health notifications |

---

**Q15. A Glue job succeeded but downstream Redshift row counts don't match source counts. How do you debug this?**

**A:**

1. **Check Glue CloudWatch logs** — look for skipped records, schema mismatches, or write errors.

2. **Add count checkpoints in the job:**
   ```python
   print(f"Records read from S3: {df.count()}")
   print(f"Records after transform: {df_transformed.count()}")
   # Compare with: SELECT COUNT(*) FROM redshift_target
   ```

3. **Check for silent drops** — Glue DynamicFrames silently drop rows with type mismatches. Enable `--enable-continuous-cloudwatch-log` and look for `DynamicRecord` errors.

4. **Query Redshift STL error tables:**
   ```sql
   SELECT * FROM stl_load_errors ORDER BY starttime DESC LIMIT 50;
   SELECT * FROM stl_loaderror_detail LIMIT 50;
   ```

5. **Check for duplicates** — mismatch could be *more* rows in Redshift, not fewer. Verify COPY didn't run twice or MERGE logic has a bug.

6. **Check S3 file completeness** — if Glue listed S3 objects before all upstream writes finished, some files may have been missed. Check S3 inventory for the partition.

7. **Check timezone bugs** — records near midnight may fall into the wrong partition due to timezone conversion errors during timestamp bucketing.

---

*Want follow-up questions, a mock interview drill, or deeper coverage of a specific AWS service? Let me know!*