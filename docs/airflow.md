# Apache Airflow — Interview Questions & Answers
### SWE III Data Engineering Interview Prep

---

> **Coverage assessment:** These questions are well-calibrated for a SWE III data engineering interview. See the **Interview Readiness Guide** at the bottom for a detailed breakdown.

---

## Table of Contents

1. [Theory](#theory)
2. [Architecture](#architecture)
3. [Practical / Coding](#practical--coding)
4. [Operations](#operations)
5. [Advanced](#advanced)
6. [Gotchas](#gotchas)
7. [Interview Readiness Guide](#interview-readiness-guide)

---

## Theory

---

### Q1. What is Apache Airflow and what problems does it solve over cron jobs?

**Answer:**

Airflow is an open-source platform to programmatically author, schedule, and monitor workflows as DAGs (Directed Acyclic Graphs).

**Cron limitations Airflow solves:**

| Problem | Cron | Airflow |
|---|---|---|
| Dependency management | ❌ None | ✅ Explicit DAG dependencies |
| Retry on failure | ❌ None | ✅ Configurable retries + backoff |
| Visibility into failures | ❌ None | ✅ Web UI, logs, alerts |
| Backfilling missed runs | ❌ Manual | ✅ `airflow dags backfill` command |
| Parameterization | ❌ None | ✅ Variables, Connections, DagRun conf |
| Operator ecosystem | ❌ None | ✅ S3, Redshift, Glue, Spark, dbt, etc. |

> **Interview tip:** One-liner: *"Cron has no dependency graph, no retry, no visibility. Airflow has all three plus backfill and a rich operator ecosystem."*

---

### Q2. What is a DAG in Airflow? What does "Directed Acyclic Graph" mean in practice?

**Answer:**

A DAG is a collection of tasks with explicit dependencies defining execution order.

- **Directed** — dependencies have direction: task A must complete before task B starts
- **Acyclic** — no cycles allowed. You cannot have A → B → A. Airflow enforces this at DAG parse time.
- **Graph** — multiple tasks connected by edges (dependencies)

**Key concepts:**
- Each Python file in the `dags/` folder defines one or more DAGs
- A DAG defines the schedule, start date, retry policy, and task dependencies
- The DAG itself does not contain data — it defines the workflow structure
- Each execution of a DAG for a specific logical date = a **DAG Run**
- Each task execution within a DAG Run = a **Task Instance**

> **Interview tip:** If asked "Can you have a cycle in Airflow?" — No. Airflow raises a cycle detection error at DAG parse time. Knowing *why* (infinite wait between tasks) shows you understand the model.

---

### Q3. Explain the Airflow execution date and the difference between `execution_date`, `data_interval_start`, and `data_interval_end`.

**Answer:**

**The confusing legacy behaviour:**

`execution_date` (legacy) was the *start* of the schedule interval — but a daily DAG with `execution_date=2024-01-10` actually processed data for `2024-01-10 → 2024-01-11`. The DAG ran at the *end* of the interval, making the name misleading.

**Airflow 2.2+ replaced this with explicit variables:**

| Variable | Meaning |
|---|---|
| `data_interval_start` | Start of the data period being processed |
| `data_interval_end` | End of the data period being processed |
| `logical_date` | Replaces `execution_date` — equals `data_interval_start` |

**Example:** A `@daily` DAG triggered on `2024-01-11`:
- `data_interval_start` = `2024-01-10 00:00:00`
- `data_interval_end` = `2024-01-11 00:00:00`

This means **Airflow always runs one interval behind** — the trigger happens after the interval completes.

```python
from airflow.decorators import task
from airflow import DAG
from datetime import datetime

with DAG("my_dag", schedule="@daily", start_date=datetime(2024,1,1)) as dag:
    @task
    def process(**context):
        ti = context["data_interval_start"]
        te = context["data_interval_end"]
        print(f"Processing data from {ti} to {te}")
        # For a run triggered 2024-01-11:
        # ti = 2024-01-10 00:00:00
        # te = 2024-01-11 00:00:00
```

> **Interview tip:** This is almost always asked and almost always gets wrong answers. Know that Airflow runs at the END of the interval and always use `data_interval_start` in SQL WHERE clauses, never `execution_date` directly.

---

### Q4. What are the different task states in Airflow and what transitions exist?

**Answer:**

**Task instance state lifecycle:**

```
none → scheduled → queued → running → success
                                    ↘ failed → up_for_retry → scheduled (loop)
                                    ↘ upstream_failed
                                    ↘ skipped
                                    ↘ deferred (Airflow 2.2+)
```

| State | Meaning |
|---|---|
| `none` | Task instance created but not yet evaluated |
| `scheduled` | Dependencies met, waiting for executor slot |
| `queued` | Sent to executor, waiting for worker |
| `running` | Being executed by a worker |
| `success` | Completed successfully |
| `failed` | Execution failed, no retries remaining |
| `up_for_retry` | Failed but retries remaining |
| `upstream_failed` | A parent task failed; this task will not run |
| `skipped` | Skipped by BranchOperator or SkipMixin |
| `deferred` | Handed to Triggerer; worker slot released |
| `removed` | Task removed from DAG definition mid-run |

> **Interview tip:** The `deferred` state (Airflow 2.2+) is important for MWAA cost optimization. It fully releases the worker slot while waiting for an external event — key for pipelines that wait hours for Glue jobs or S3 files.

---

### Q5. What are trigger rules in Airflow and when would you use something other than the default?

**Answer:**

Trigger rules define when a task is allowed to run based on upstream task states.

| Trigger Rule | Runs when... |
|---|---|
| `all_success` *(default)* | All upstream tasks succeeded |
| `all_failed` | All upstream tasks failed |
| `all_done` | All upstream tasks are done (any state) |
| `one_success` | At least one upstream task succeeded |
| `one_failed` | At least one upstream task failed |
| `none_failed` | No upstream tasks failed (success or skipped is fine) |
| `none_failed_min_one_success` | No failures AND at least one success |
| `always` | Unconditionally |

**Practical example — notification/cleanup task:**

```python
from airflow.utils.trigger_rule import TriggerRule
from airflow.operators.python import PythonOperator

# This task runs whether the pipeline succeeded OR failed
notify_task = PythonOperator(
    task_id="send_slack_alert",
    python_callable=send_notification,
    trigger_rule=TriggerRule.ALL_DONE,
    dag=dag
)

cleanup_task = PythonOperator(
    task_id="cleanup_temp_files",
    python_callable=cleanup,
    trigger_rule=TriggerRule.ALL_DONE,
    dag=dag
)
```

> **Interview tip:** Common scenario: *"You have 5 pipeline tasks. You want a Slack notification to always fire at the end, whether the pipeline succeeded or failed. How?"* — `trigger_rule=ALL_DONE` on the notification task. Candidates who only know `ALL_SUCCESS` miss this.

---

## Architecture

---

### Q6. Describe Airflow's core architecture components and their responsibilities.

**Answer:**

```
┌─────────────────────────────────────────────────────────────┐
│                     Airflow Architecture                     │
├────────────────┬────────────────┬───────────────────────────┤
│   Scheduler    │   Webserver    │     DAG Processor          │
│  (brain)       │   (UI)         │   (Airflow 2.3+)           │
├────────────────┴────────────────┴───────────────────────────┤
│                      Executor                                │
│  Local | Celery | Kubernetes                                 │
├──────────────────────┬──────────────────────────────────────┤
│   Metadata DB        │   Message Broker (Celery only)        │
│  (Postgres/MySQL)    │   Redis / RabbitMQ                    │
└──────────────────────┴──────────────────────────────────────┘
```

| Component | Responsibility |
|---|---|
| **Scheduler** | Parses DAG files, creates DagRuns, submits ready tasks to executor, detects zombies |
| **Executor** | Defines *how* tasks run (local subprocess, Celery worker, K8s pod) |
| **Workers** | Actually execute task code (Celery/K8s modes) |
| **Webserver** | Serves the Airflow UI; reads metadata DB |
| **DAG Processor** | Parses DAG files (decoupled from scheduler in 2.3+) |
| **Metadata DB** | Stores all state — DAG runs, task instances, connections, variables |
| **Message Broker** | (CeleryExecutor only) Queues task execution requests between scheduler and workers |

> **Interview tip:** Know which components are **stateless** (webserver, workers — scale horizontally) vs **stateful** (metadata DB — the single source of truth). If asked *"What happens if the scheduler restarts?"* — it re-reads the metadata DB and resumes from last known state.

---

### Q7. What is the difference between LocalExecutor, CeleryExecutor, and KubernetesExecutor?

**Answer:**

| | LocalExecutor | CeleryExecutor | KubernetesExecutor |
|---|---|---|---|
| **How tasks run** | Subprocesses on scheduler machine | Distributed Celery workers | One pod per task |
| **Scalability** | Single machine limit | Horizontally scalable | Horizontally scalable |
| **Idle cost** | Low | Workers always running | No idle cost (pods destroyed) |
| **Cold start** | None | None | ~10-30s pod spin-up |
| **Complexity** | Low | Medium (broker needed) | High (K8s needed) |
| **Best for** | Dev / small pipelines | High-throughput / many concurrent tasks | Variable workloads, resource-heavy tasks |

> **Interview tip (AWS context):** MWAA uses CeleryExecutor by default. For cost optimization on MWAA — **deferrable operators** reduce worker slot usage by releasing the slot while waiting for external events (S3 sensor, Glue job completion). This directly reduces MWAA worker costs.

---

### Q8. How does Airflow's scheduler work internally — what is the scheduler loop?

**Answer:**

The scheduler runs a continuous loop:

1. **DAG file parsing** — repeatedly parses Python DAG files to detect new/changed DAGs and serialize them to the metadata DB
2. **DagRun creation** — for each active DAG, checks if a new DagRun should be created based on schedule and last run time
3. **Task dependency evaluation** — evaluates which task instances have all dependencies met and are schedulable
4. **Executor submission** — submits ready task instances to the executor (up to parallelism limits)
5. **State sync** — polls the executor for task state updates and writes them to the metadata DB
6. **Zombie detection** — finds task instances whose worker heartbeat has gone stale (worker crashed) and marks them failed

**Scheduler performance bottlenecks:**
- Too many DAG files → slow parsing → scheduling lag
- Fix: use `.airflowignore` to exclude non-DAG files, split large DAGs, enable DAG serialization

> **Interview tip:** DAG serialization (enabled by default in Airflow 2.x) stores parsed DAGs in the metadata DB so the webserver doesn't re-parse Python files on every page load. This is a significant UI performance improvement for large deployments.

---

## Practical / Coding

---

### Q9. Write a DAG that reads from S3, runs a Glue job, and loads results into Redshift — with proper error handling.

**Answer:**

```python
from airflow import DAG
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor
from airflow.providers.amazon.aws.operators.glue import GlueJobOperator
from airflow.providers.amazon.aws.operators.redshift_sql import RedshiftSQLOperator
from datetime import datetime, timedelta

default_args = {
    "owner": "data-eng",
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,       # 5m, 10m, 20m backoff
    "execution_timeout": timedelta(hours=2),
    "on_failure_callback": notify_slack,     # custom Slack callback
}

with DAG(
    dag_id="s3_glue_redshift_pipeline",
    default_args=default_args,
    schedule="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["data-engineering", "orders"],
) as dag:

    # Wait for upstream data — reschedule mode releases worker slot while waiting
    wait_for_data = S3KeySensor(
        task_id="wait_for_s3_file",
        bucket_name="my-data-lake",
        bucket_key="landing/orders/{{ ds }}/data.parquet",
        aws_conn_id="aws_default",
        mode="reschedule",    # releases worker slot while waiting
        poke_interval=60,
        timeout=3600,
    )

    # Run Glue ETL
    run_glue_job = GlueJobOperator(
        task_id="run_glue_etl",
        job_name="orders-transform-job",
        script_args={
            "--execution_date": "{{ ds }}",
            "--source_path": "s3://my-data-lake/landing/orders/{{ ds }}/",
            "--target_path": "s3://my-data-lake/processed/orders/{{ ds }}/",
        },
        aws_conn_id="aws_default",
        wait_for_completion=True,
        num_of_dpus=10,
    )

    # COPY into Redshift
    load_to_redshift = RedshiftSQLOperator(
        task_id="load_to_redshift",
        redshift_conn_id="redshift_default",
        sql="""
            COPY orders_staging
            FROM 's3://my-data-lake/processed/orders/{{ ds }}/'
            IAM_ROLE 'arn:aws:iam::123456789:role/RedshiftS3Role'
            FORMAT AS PARQUET;
        """,
    )

    # Validate the load succeeded — fails DAG if 0 rows loaded
    validate_load = RedshiftSQLOperator(
        task_id="validate_row_count",
        redshift_conn_id="redshift_default",
        sql="""
            SELECT CASE WHEN COUNT(*) > 0 THEN 1
            ELSE 1/0 END
            FROM orders_staging
            WHERE order_date = '{{ ds }}';
        """,
    )

    wait_for_data >> run_glue_job >> load_to_redshift >> validate_load
```

**Three production details to highlight:**

1. `mode='reschedule'` on sensors — releases the worker slot while waiting
2. `retry_exponential_backoff=True` — avoids hammering a struggling service
3. A validation task after the load that fails the DAG if 0 rows — always validate what you just loaded

---

### Q10. What is XCom in Airflow and what are its limitations? How do you pass large data between tasks?

**Answer:**

XCom (cross-communication) is Airflow's mechanism for tasks to share small amounts of data via the metadata database.

**The critical limitation:** XComs are stored in the metadata DB — not designed for large payloads. Storing DataFrames or large JSON blobs bloats the DB and degrades scheduler performance.

**Rule:** XCom is for **metadata** — file paths, job IDs, row counts, status strings. Never put DataFrames in XCom.

```python
from airflow.decorators import task, dag
from datetime import datetime

@dag(schedule="@daily", start_date=datetime(2024,1,1))
def xcom_example():

    @task
    def extract() -> str:
        # Write data to S3, return the PATH — not the data itself
        s3_path = write_to_s3(fetch_data())
        return s3_path   # XCom stores a short string

    @task
    def transform(s3_path: str) -> str:
        df = read_from_s3(s3_path)          # read via path
        result_path = write_transformed(df)
        return result_path

    @task
    def load(s3_path: str):
        copy_to_redshift(s3_path)

    path1 = extract()
    path2 = transform(path1)
    load(path2)

xcom_example()
```

**For large data:** write to S3 and pass the S3 path via XCom. Alternatively, configure a **custom XCom backend** (Airflow 2.x) to store XCom values in S3 instead of the metadata DB.

> **Interview tip:** *"Never store DataFrames in XCom"* is a classic trap. The follow-up is always: *"So how DO you pass a DataFrame between tasks?"* — S3 path via XCom, or redesign so transformation happens in a single task.

---

### Q11. What is the TaskFlow API and how is it different from the traditional operator-based approach?

**Answer:**

The TaskFlow API (Airflow 2.0+) lets you write DAGs as decorated Python functions using `@task` and `@dag` decorators.

| Aspect | Traditional | TaskFlow API |
|---|---|---|
| Task creation | Instantiate `PythonOperator` objects | `@task` decorator on function |
| Dependencies | Manual `>>` and `<<` wiring | Automatic — passing return value creates dependency |
| XCom | Manual `xcom_push()` / `xcom_pull()` | Return value auto-becomes XCom |
| AWS operators | Supported | Not applicable (still use traditional) |

**Best practice: mix both approaches**

```python
from airflow.decorators import task, dag
from airflow.providers.amazon.aws.operators.glue import GlueJobOperator
from datetime import datetime

@dag(schedule="@daily", start_date=datetime(2024,1,1))
def mixed_dag():

    # TaskFlow for Python logic
    @task
    def get_config(ds=None) -> dict:
        return {"date": ds, "source": f"s3://bucket/landing/{ds}/"}

    @task
    def validate_result(row_count: int):
        if row_count == 0:
            raise ValueError("No rows loaded — pipeline failed")

    @task
    def get_row_count(ds=None) -> int:
        return query_redshift(f"SELECT COUNT(*) FROM orders WHERE dt='{ds}'")

    # Traditional operator for AWS Glue (no @task equivalent)
    config = get_config()

    glue_job = GlueJobOperator(
        task_id="run_glue",
        job_name="orders-etl",
        script_args={"--date": "{{ ds }}"},
    )

    row_count = get_row_count()
    validate = validate_result(row_count)

    # Mix: wire TaskFlow and traditional operators
    config >> glue_job >> row_count >> validate

mixed_dag()
```

> **Interview tip:** Candidates who say *"TaskFlow replaces all operators"* miss that AWS/DB operators don't have `@task` equivalents. Knowing how to mix both cleanly is a strong practical signal.

---

## Operations

---

### Q12. How do you manage Airflow connections and variables securely in production?

**Answer:**

Never hardcode credentials in DAG files. Options ranked by security:

| Option | Security | Notes |
|---|---|---|
| AWS Secrets Manager backend | ⭐⭐⭐ Best | Zero credentials in metadata DB |
| Environment variables | ⭐⭐⭐ Best | Not visible in UI, not stored in DB |
| HashiCorp Vault | ⭐⭐⭐ Best | Another secrets backend option |
| Airflow UI / metadata DB | ⭐⭐ OK | Encrypted with Fernet key, visible in UI |

**AWS Secrets Manager backend (recommended for AWS/MWAA):**

```ini
# airflow.cfg
[secrets]
backend = airflow.providers.amazon.aws.secrets.secrets_manager.SecretsManagerBackend
backend_kwargs = {
  "connections_prefix": "airflow/connections",
  "variables_prefix": "airflow/variables",
  "region_name": "ap-south-1"
}
```

```python
# Secrets stored in AWS Secrets Manager as:
# airflow/connections/redshift_default → {"conn_type":"redshift","host":"...","login":"..."}
# airflow/variables/s3_bucket          → "my-data-lake-bucket"

# In DAG — same API, no code change:
from airflow.models import Variable
bucket = Variable.get("s3_bucket")   # resolved from Secrets Manager at runtime
```

> **Interview tip:** The Secrets Manager backend resolves transparently — same `Variable.get()` API, no DAG code changes. Mention Fernet key rotation for the fallback DB storage case. For MWAA: store connections with prefix `airflow/connections/` and MWAA resolves them automatically.

---

### Q13. How do you backfill in Airflow and what are the gotchas?

**Answer:**

Backfilling reruns a DAG for historical dates — useful when you fix a bug, add a new metric, or onboard a new pipeline.

```bash
# Backfill CLI
airflow dags backfill \
  -s 2024-01-01 \
  -e 2024-01-31 \
  --max-active-runs 5 \   # parallelism
  my_dag
```

**Key gotchas:**

| Gotcha | Detail |
|---|---|
| `catchup=True` required | Or explicitly specify dates on command line |
| Sequential by default | Add `--max-active-runs N` to parallelize |
| Race conditions | Parallel backfill + non-partition-isolated writes = duplicates |
| Skips existing successes | By design — override with `--reset-dagruns` |
| Sensor + historical data | Sensors waiting for files need those files to exist for historical dates |
| **Idempotency is critical** | Every task must produce the same result if run multiple times for same date |

> **Interview tip:** Idempotency is the most important point. If your load task does `INSERT` without checking for existing data, backfill creates duplicates. Always use UPSERT, `INSERT...WHERE NOT EXISTS`, or partition overwrite patterns so backfill is safe to run multiple times.

---

### Q14. How do you monitor Airflow in production and what alerts would you set up?

**Answer:**

**Monitoring layers:**

```
Built-in UI   → DAG run history, task state timelines, Gantt charts, task logs
Callbacks     → on_failure_callback, on_sla_miss_callback at DAG/task level
StatsD metrics → scheduler metrics → CloudWatch / Datadog
```

**Key metrics to alert on:**

| Metric | Alert condition |
|---|---|
| Scheduler heartbeat age | > 60s → scheduler down |
| Task failure rate | Spike > baseline → upstream issue |
| Executor queue depth | High → workers overwhelmed |
| DAG parse time | > 30s → too many/complex DAGs |
| Zombie task count | > 0 → worker crash pattern |

```python
# DAG-level SLA + failure callback
from datetime import timedelta

def on_failure_alert(context):
    dag_id = context["dag"].dag_id
    task_id = context["task_instance"].task_id
    exec_date = context["execution_date"]
    send_slack_message(
        f":red_circle: *{dag_id}.{task_id}* failed\n"
        f"Execution date: {exec_date}\n"
        f"Log: {context['task_instance'].log_url}"
    )

default_args = {
    "on_failure_callback": on_failure_alert,
    "sla": timedelta(hours=3),   # alert if task not done in 3h even if still running
}
```

> **Interview tip:** SLA miss callbacks are underused — most teams only set failure callbacks. An SLA miss alert fires even if the task *eventually* succeeds but was too slow, which is exactly the case for data freshness SLAs.

---

## Advanced

---

### Q15. What are dynamic DAGs and dynamic task mapping in Airflow 2.3+?

**Answer:**

**Dynamic task mapping** lets a single task fan out into N parallel instances at runtime, where N is determined by the actual data — not hardcoded.

```python
from airflow.decorators import task, dag
from datetime import datetime

@dag(schedule="@daily", start_date=datetime(2024,1,1))
def dynamic_table_profiler():

    @task
    def get_tables() -> list[str]:
        # Returns different number of tables each run based on data catalog
        return query_glue_catalog("SELECT table_name FROM information_schema.tables")

    @task
    def profile_table(table_name: str) -> dict:
        # This task runs N times in parallel — once per table name
        return run_profiling_query(table_name)

    @task
    def summarize_results(profiles: list[dict]):
        send_quality_report(profiles)

    tables = get_tables()
    # .expand() creates one task instance per table — dynamically at runtime
    profiles = profile_table.expand(table_name=tables)
    summarize_results(profiles)

dynamic_table_profiler()
```

**Dynamic DAGs vs Dynamic task mapping:**

| | Dynamic DAGs | Dynamic task mapping |
|---|---|---|
| How | Python loop in DAG file creates multiple DAG objects | `.expand()` creates multiple task instances at runtime |
| Visibility | Separate DAG entries in UI (cluttered) | Single task in UI with N mapped instances |
| Runtime flexibility | Fixed at parse time | Adapts to actual data each run |
| Airflow version | All versions | 2.3+ |

> **Interview tip:** Dynamic task mapping is one of the most powerful Airflow 2.x features and relatively underknown. Key use case: processing a *variable* number of partitions, tables, or files without hardcoding the fan-out count.

---

### Q16. What are deferrable operators in Airflow and how do they improve resource efficiency?

**Answer:**

Traditional sensors occupy a worker slot while waiting. Deferrable operators (Airflow 2.2+) fully release the worker slot by handing off to the **Triggerer** — a new lightweight async component.

```
Traditional sensor (poke/reschedule mode):
  Worker slot OCCUPIED → polling every 60s → slot held for hours

Deferrable operator:
  Task defers → state saved to metadata DB → worker slot RELEASED
  Triggerer watches for event using asyncio (one Triggerer handles thousands)
  Event fires → Triggerer re-queues task → worker slot acquired again
```

```python
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor

# Traditional — holds worker slot
traditional = S3KeySensor(
    task_id="wait_traditional",
    bucket_name="my-bucket",
    bucket_key="data/{{ ds }}/file.parquet",
    mode="reschedule",
)

# Deferrable — fully releases worker slot, uses Triggerer
deferrable = S3KeySensor(
    task_id="wait_deferrable",
    bucket_name="my-bucket",
    bucket_key="data/{{ ds }}/file.parquet",
    deferrable=True,    # single parameter change
)
```

> **Interview tip (MWAA):** For MWAA, deferrable operators are the go-to answer for *"how do you reduce Airflow costs?"* Long pipelines waiting hours for Glue jobs or S3 files save significant worker costs by switching to deferrable mode.

---

### Q17. How would you design an Airflow pipeline for a late-arriving data scenario with reprocessing?

**Answer:**

**The problem:** Event happened Jan 10, data arrives Jan 13. The Jan 10 DAG run already completed successfully.

**Solutions:**

**Option 1 — External trigger via REST API** *(most common)*

An S3 event triggers a Lambda that calls the Airflow REST API to trigger a DAG run with the correct logical date:

```python
# Lambda triggered by S3 late arrival event
import requests

requests.post(
    "http://airflow-webserver/api/v1/dags/orders_pipeline/dagRuns",
    json={
        "logical_date": "2024-01-10T00:00:00Z",  # the late data's date
        "conf": {
            "late_arrival": True,
            "source_path": "s3://bucket/landing/orders/2024-01-10/late/"
        }
    },
    auth=("airflow", "password")
)
```

**Option 2 — Dataset-aware scheduling (Airflow 2.4+)**

Define Datasets that downstream DAGs depend on. When late data updates a Dataset, downstream DAGs automatically re-trigger.

**Option 3 — Late window sensor**

Keep a daily DAG running for N days after its execution date, checking for late arrivals. Use `execution_timeout` to bound how long it waits.

**Critical requirement — idempotency:**

The DAG must be safe to re-run for the same date. Use:
- Partition overwrite (not append) in Redshift/Iceberg
- `MERGE` / UPSERT instead of INSERT
- `dynamic` overwrite mode in Spark

> **Interview tip:** This ties directly to Iceberg's snapshot model and partition evolution patterns. Idempotency is what makes late data handling safe — without it, reprocessing creates duplicates.

---

## Gotchas

---

### Q18. What are the most common Airflow anti-patterns that cause production problems?

**Answer:**

**1. Top-level code in DAG files** *(most dangerous)*

Any code at module level runs every time the scheduler parses the DAG file (every ~30 seconds). API calls, DB queries, or heavy imports here crash or slow the scheduler.

```python
# ❌ WRONG — runs on every scheduler parse cycle
import requests
tables = requests.get("https://api.example.com/tables").json()  # runs every 30s!

with DAG("my_dag", ...) as dag:
    ...

# ✅ CORRECT — inside task callable, runs only during execution
@task
def get_tables():
    return requests.get("https://api.example.com/tables").json()
```

**2. Using `datetime.now()` instead of Airflow template variables**

```python
# ❌ WRONG — breaks backfill, non-idempotent
def process():
    date = datetime.now().strftime("%Y-%m-%d")  # always today's date

# ✅ CORRECT — uses the logical execution date
def process(**context):
    date = context["data_interval_start"].strftime("%Y-%m-%d")
```

**3. Storing large objects in XCom** — bloats metadata DB.

**4. Not setting `catchup=False`** — new DAGs with historical `start_date` immediately queue hundreds of backfill runs.

**5. Catching all exceptions** — swallowing exceptions makes failed tasks appear successful.

```python
# ❌ WRONG
def my_task():
    try:
        do_something()
    except Exception:
        pass  # Airflow thinks it succeeded!

# ✅ CORRECT — let exceptions propagate
def my_task():
    do_something()  # exception propagates → Airflow retries/fails correctly
```

> ⚠️ **Watch out:** The top-level code anti-pattern is the most dangerous. One developer adding `requests.get(...)` at module level can take down the entire scheduler if the API is slow or down. Code review should specifically check for this.

---

### Q19. How do you handle secrets and avoid hardcoding credentials — and what is the Fernet key?

**Answer:**

**Fernet key** is Airflow's symmetric encryption key used to encrypt sensitive values (passwords, connection extras) stored in the metadata DB.

```bash
# Generate a Fernet key
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# Set via environment variable — never hardcode in airflow.cfg
export AIRFLOW__CORE__FERNET_KEY="your-generated-key-here"
```

**Key risks:**
- Losing the Fernet key = all encrypted values in DB become **unreadable** (unrecoverable)
- Key rotation requires decrypting all values with the old key + re-encrypting with the new key
- Never commit the Fernet key to version control

**Best practice for AWS:**

```
Fernet key → store in AWS Secrets Manager or Parameter Store
             inject as env var AIRFLOW__CORE__FERNET_KEY into scheduler/webserver/workers

Connections → use Secrets Manager backend (credentials never stored in DB)
             zero Fernet risk for credentials
```

> **Interview tip:** Fernet key loss is an unrecoverable event for DB-stored credentials. This is the strongest argument for the Secrets Manager backend: zero credentials in the DB means the Fernet key only protects variables, not credentials.

---

## Interview Readiness Guide

### Is this content good for a SWE III Data Engineering interview?

**Yes — and here's why:**

#### What SWE III means for Airflow

A SWE III / Senior data engineer is expected to go beyond "I know how to write a DAG." The bar is: *Can you design, operate, and debug Airflow in production? Do you understand the failure modes? Can you make trade-off decisions?*

#### Coverage map

| Topic | Difficulty | SWE III relevance |
|---|---|---|
| DAG / execution date model | Medium | ⭐⭐⭐ Always asked |
| Trigger rules | Medium | ⭐⭐⭐ Frequently asked |
| Architecture components | Medium | ⭐⭐⭐ Always asked |
| Executor comparison | Medium-Hard | ⭐⭐⭐ Always asked for senior roles |
| S3 → Glue → Redshift DAG | Practical | ⭐⭐⭐ Live coding / design |
| XCom limitations | Medium | ⭐⭐⭐ Classic trap question |
| TaskFlow API | Medium | ⭐⭐ Increasingly asked |
| Secrets / Fernet key | Medium | ⭐⭐⭐ Always asked on AWS roles |
| Backfill + idempotency | Hard | ⭐⭐⭐ Senior signal |
| SLA monitoring | Medium | ⭐⭐ Good differentiator |
| Dynamic task mapping | Hard | ⭐⭐ Strong differentiator (Airflow 2.x) |
| Deferrable operators | Hard | ⭐⭐⭐ Critical for MWAA cost questions |
| Late-arriving data | Hard | ⭐⭐⭐ System design signal |
| Anti-patterns / top-level code | Hard | ⭐⭐⭐ Production experience signal |

#### What will differentiate you

Three answers that signal genuine production experience over tutorial-level knowledge:

1. **Deferrable operators + Triggerer** — most candidates know sensors, few know `deferrable=True` releases the worker slot. On MWAA, this is a direct cost answer.

2. **Top-level code anti-pattern** — knowing *why* it breaks the scheduler (parsed every 30s) and catching it in code review shows real operational experience.

3. **Idempotency in context** — connecting backfill safety → late-arriving data → Iceberg partition overwrite → UPSERT patterns shows you think architecturally, not just at the task level.

#### Topics not covered (consider adding)

- **MWAA-specific configuration** (worker class sizing, environment variables)
- **Airflow on Kubernetes** (KubernetesPodOperator, pod templates)
- **dbt + Airflow integration** (DbtTaskGroup, BashOperator vs dbt Cloud)
- **Data-aware scheduling / Datasets** (Airflow 2.4+)
- **High availability** (multiple schedulers, active-active setup)

---

*Generated for SWE III Data Engineering interview preparation.*
*Last updated: 2024*