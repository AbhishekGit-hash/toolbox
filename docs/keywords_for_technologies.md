# Technologies and Core Features

---

## Table of Contents

1. [LangChain](#langchain)
2. [LangGraph](#langgraph)
3. [RAG Pipelines](#ragpipelines)
4. [MCP](#mcp)

---

## LangChain

---

Framework for building LLM Applications. It solves the problem of orchestration, chaning together LLM calls, tool use memory and data retrieval in a structured manner.

| Feature | Description |
|---|---|
| Chains | A sequence of calls to LLMs, tools, or data sources wired together in a fixed, predetermined order. Each step's output feeds into the next, making the execution path transparent and predictable. |
| Agents | Autonomous reasoning loops where an LLM decides at runtime which tools to invoke and in what order. Unlike chains, the execution path is dynamic — the model acts as a planner and executor until a stopping condition is met. |
| Tools | Functions or APIs exposed to an LLM so it can interact with the outside world — search engines, calculators, databases, REST APIs. Each tool has a name, description, and input schema that the model uses to decide when and how to call it. |
| Memory | Mechanisms for persisting state across turns in a conversation. Can be short-term (in-context message history) or long-term (vector store or key-value store). Without explicit memory, each LLM call is stateless. In-memory types: ConverstaionBufferMemory, ConversationBufferWindowMemory, ConversationSummaryMemory, ConversationSummaryBufferMemory, ConversationEntityMemory |
| Retrievers | Interfaces that fetch relevant documents from a knowledge source given a query. Commonly backed by a vector store (semantic search) or keyword index. Used in RAG pipelines to ground LLM responses in external data. |
| Model | A wrapper around a language model provider (OpenAI, Anthropic, Cohere, local models, etc.) that normalises the call interface. Exposes methods like `invoke`, `stream`, and `batch` and handles API authentication, retries, and token counting. |
| Prompt Templates | Reusable, parameterised text blueprints that produce a formatted prompt at runtime. Support variable interpolation, few-shot examples, and chat message formatting, separating prompt logic from application code. |
| Output Parsers | Post-processors that transform raw LLM text output into structured data — JSON objects, Pydantic models, lists, or custom types. Provide a schema contract between the model's free-form output and downstream code that needs typed values. |
| LangChain Expression Language (LCEL) | Declarative syntax for composing chains using the Pipe Operator (`\|`). Every component — prompts, model, output parsers, retrievers — implements a `Runnable` interface with `invoke`, `stream`, and `batch` methods. Piping them creates a chain where the output of each step is an input to the next step. LCEL provides in-built streaming, async support, parallel execution via `RunnableParallel`, and automatic LangSmith tracing. |


---

## LangGraph

---

Framework for building stateful multi-step AI workflows as directed graphs. LangChain chains are linear or branching, but they lack persistent state and can't loop. 

| Feature | Description |
|---|---|
| State | A shared data structure (typically a `TypedDict` or Pydantic model) that represents the entire snapshot of your application at any point in time. Every node reads from and writes to this object. LangGraph merges node outputs back into state using a reducer — by default last-write-wins, but custom reducers (e.g. appending to a list) can be defined per field. |
| Nodes | The units of work in a graph — plain Python functions or Runnables that receive the current state and return a partial update to it. Each node performs one logical step: calling an LLM, invoking a tool, running a retriever, or executing arbitrary business logic. |
| Edges | Connections that define execution flow between nodes. A **normal edge** always routes from node A to node B. A **conditional edge** calls a routing function on the current state and returns the name of the next node to visit, enabling dynamic branching (e.g. agent → tool call or agent → END). |
| StateGraph | The top-level builder class that wires nodes and edges into a compiled graph. You register nodes with `add_node()`, define flow with `add_edge()` / `add_conditional_edges()`, set the entrypoint with `set_entry_point()`, and call `.compile()` to produce an executable `CompiledGraph` that exposes `invoke`, `stream`, and `batch`. |
| Checkpointer | A persistence layer attached at compile time (`compile(checkpointer=...)`) that snapshots the full state after every node execution. Enables pause-and-resume, human-in-the-loop interrupts, time-travel debugging, and fault-tolerant long-running workflows. Built-in backends include in-memory, SQLite, and Postgres. |
| Interrupt / Human-in-the-loop | A mechanism to pause graph execution mid-run at a designated node and hand control back to a human or external system. Execution resumes by invoking the graph again with the same `thread_id`. Used for approval flows, ambiguity resolution, and supervised agent steps. |
| Send API | A low-level primitive (`Send(node, state)`) used inside conditional edge routers to dispatch multiple independent state copies to the same node simultaneously. The primary way to implement dynamic fan-out — e.g. spawning one sub-task node per item in a list — before fan-in via a reducer. |
| Subgraphs | Full `CompiledGraph` instances embedded as a node inside a parent graph. Each subgraph can have its own independent state schema; a state key mapping connects parent and child state. Enables modular, reusable workflow components and multi-agent architectures where each agent is its own graph. |
| Multi-agent / Supervisor | A higher-level pattern (not a single class) where one graph acts as a supervisor that routes work to specialised agent subgraphs via conditional edges. Each worker agent operates independently and returns results to the supervisor, which decides the next step or terminates. |

---

## RAG Pipelines

---

LC = LangChain, LG = LangGraph

| Phase | Keyword | Framework | Description |
|---|---|---|---|
| **Ingestion** | Document loaders | LC | Load raw content from PDFs, URLs, databases, S3, Notion, etc. into a uniform `Document` object. |
| **Ingestion** | Text splitters | LC | Break large documents into smaller chunks. Strategies include recursive character, token, semantic, and markdown-aware splitting. |
| **Ingestion** | Chunk overlap | LC | Number of tokens/characters shared between adjacent chunks to preserve context at boundaries and avoid hard splits mid-sentence. |
| **Ingestion** | Metadata | LC | Arbitrary key-value pairs attached to each `Document` (source, page, date). Used later for filtering during retrieval. |
| **Indexing** | Embeddings | LC | Dense vector representations of text produced by a model (OpenAI, Cohere, HuggingFace). Semantic similarity = cosine distance between vectors. |
| **Indexing** | Vector store | LC | Database that indexes embedding vectors for fast approximate nearest-neighbour search. Examples: Chroma, FAISS, Pinecone, pgvector, Weaviate. |
| **Indexing** | Indexing API | LC | LangChain utility that tracks document hashes to avoid re-embedding unchanged content on incremental updates. |
| **Indexing** | Sparse retrieval (BM25) | LC | Keyword-based ranking as an alternative or complement to dense vectors. Useful for exact-term matches that embeddings can miss. |
| **Retrieval** | Retriever interface | LC | The standard `BaseRetriever` abstraction with `get_relevant_documents()`. Any vector store, BM25 index, or custom source can implement it. |
| **Retrieval** | Similarity search | LC | Fetch the top-k chunks whose embeddings are closest to the query embedding. The default retrieval strategy. |
| **Retrieval** | MMR | LC | Maximal Marginal Relevance — balances relevance with diversity by penalising chunks too similar to already-selected results. |
| **Retrieval** | Multi-query retriever | LC | Uses an LLM to rewrite the original query into multiple variations, runs each, then merges results to improve recall. |
| **Retrieval** | Contextual compression | LC | Post-retrieval step that uses an LLM or embeddings to strip irrelevant sentences from each retrieved chunk before passing to the generator. |
| **Retrieval** | Hybrid search | LC | Combines dense (semantic) and sparse (BM25) scores, usually via Reciprocal Rank Fusion, to improve retrieval across different query types. |
| **Retrieval** | Self-query retriever | LC | LLM parses a natural-language query into a semantic search + a structured metadata filter (e.g. "papers from 2023 about transformers"). |
| **Retrieval** | Parent document retriever | LC | Indexes small child chunks for precision but returns the larger parent document for richer context when a child chunk is matched. |
| **Retrieval** | Re-ranking | LC | A second-pass model (e.g. Cohere Rerank, cross-encoder) that re-scores the top-k retrieved chunks by relevance before sending to the LLM. |
| **Generation** | Prompt template | LC | Wraps retrieved context + user question into a structured prompt. Typically a `ChatPromptTemplate` with a system message and a `{context}` variable. |
| **Generation** | Stuff chain | LC | Simplest strategy — concatenate all retrieved chunks into a single context block and pass to the LLM in one call. Works until the context window fills up. |
| **Generation** | Map-reduce chain | LC | Process each chunk independently (map), then summarise or merge the individual answers (reduce). Handles more documents than fit in one context window. |
| **Generation** | Refine chain | LC | Iteratively improves a running answer by processing one chunk at a time, feeding the previous answer and the next chunk into each LLM call. |
| **Generation** | Citations / source tracking | LC | Preserving document metadata through the pipeline so the final answer can reference which source chunks it drew from. |
| **Advanced RAG** | HyDE | LC | Hypothetical Document Embeddings — generate a fake answer to the query, embed it, then use that embedding for retrieval instead of the raw question. |
| **Advanced RAG** | RAG fusion | LC | Generate multiple query variants, retrieve for each, then merge and re-rank all results using Reciprocal Rank Fusion before generation. |
| **Advanced RAG** | Corrective RAG (CRAG) | LG | A LangGraph loop that grades retrieved documents; if relevance is low, it triggers a web search or re-retrieval before proceeding to generation. |
| **Advanced RAG** | Self-RAG | LG | The LLM reflects on whether retrieval is even needed, grades retrieved chunks, and critiques its own generated answer — all as conditional graph edges. |
| **Advanced RAG** | Agentic RAG | LG | An agent node decides at runtime whether to retrieve, which retriever to call, or whether to answer from memory — retrieval becomes a tool, not a fixed step. |
| **Advanced RAG** | Adaptive RAG | LG | Routes each query to a different retrieval strategy (simple lookup, multi-step, web search) based on a classifier that judges query complexity. |
| **Memory & State** | Conversation memory | LC | Stores past turns (buffer, summary, or token-windowed) and injects them into each prompt so the RAG chain is aware of conversation history. |
| **Memory & State** | Checkpointer | LG | Persists full graph state after each node, enabling multi-turn RAG conversations with pause-and-resume and per-thread history isolation. |
| **Memory & State** | Thread / session ID | LG | Key passed to a checkpointer to scope state to a specific user session, allowing parallel conversations with independent memory. |
| **Evaluation** | LangSmith | Both | Tracing and evaluation platform. Captures every LLM call, retriever call, and chain step with latency, token counts, and inputs/outputs. |
| **Evaluation** | RAG evaluation metrics | Both | Faithfulness (answer grounded in context?), answer relevancy, context precision, and context recall — often computed via RAGAS or LangSmith evaluators. |
| **Evaluation** | Output parsers | LC | Structure the LLM's final answer (JSON, Pydantic, XML) so downstream code or evaluation harnesses can consume typed results reliably. |