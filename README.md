<div align="center">
  <a href="https://vectoramp.com/">
    <picture>
      <source media="(prefers-color-scheme: light)" srcset="https://vectoramp.com/logo-full-light.svg">
      <source media="(prefers-color-scheme: dark)" srcset="https://vectoramp.com/logo-full-dark.svg">
      <img alt="VectorAmp Logo" src="https://vectoramp.com/logo-full-dark.svg" width="50%">
    </picture>
  </a>
</div>

# VectorAmp Ruby SDK

Official Ruby client for the VectorAmp API.

- Default API: `https://api.vectoramp.com`
- Auth: `X-Api-Key`
- Transport abstraction: REST today, designed so gRPC can be added later
- Licensed under Apache-2.0.

## Installation

Add to your Gemfile:

```ruby
gem "vector_amp"
```

Or install from a local checkout while developing:

```bash
bundle install
```

## Quick start

```ruby
require "vector_amp"

# api_key defaults to ENV["VECTORAMP_API_KEY"]; base_url defaults to production.
client = VectorAmp::Client.new

# One-call create: only a name is required. The SDK defaults to the managed
# vectoramp/VectorAmp-Embedding-4B model, infers dim (2560), metric "cosine",
# and always uses the SABLE index (index type is never exposed).
dataset = client.datasets.create(name: "product-docs")

# Create/get/list return VectorAmp::Dataset resources. Prefer the object->method
# style: call helpers directly on the returned dataset.
dataset.add_texts(
  ["VectorAmp is powered by SABLE."],
  metadata: { source: "readme" }
)

# Add raw vectors. Ids may be strings or integers; integer ids stay numbers.
dataset.insert(vectors: [
  { id: 1, values: [0.1, 0.2, 0.3], metadata: { title: "Intro" } },
  { id: "doc-002", values: [0.4, 0.5, 0.6], metadata: { title: "Details" } }
])

results = dataset.search("What powers VectorAmp?", top_k: 5, include_documents: true)
answer = dataset.ask("What powers VectorAmp?")
```

### Creating datasets

```ruby
# Minimal: name only. Embedding config is omitted so VectorAmp uses
# the managed VectorAmp-Embedding-4B model and infers dim 2560.
client.datasets.create(name: "docs")

# Enable hybrid (dense + sparse) search.
client.datasets.create(name: "docs", hybrid: true)

# Optional BYOM: use OpenAI only when you intentionally want that provider
# (dim inferred from the model).
client.datasets.create(name: "openai-docs", embedding: VectorAmp::Embedding.openai("large"))

# Custom/unknown model: pass dim explicitly.
client.datasets.create(name: "docs", embedding: { provider: "acme", model: "acme-embed" }, dim: 1024)
```

## Configuration

```ruby
client = VectorAmp::Client.new(
  api_key: "va_...",
  base_url: "https://api.vectoramp.com",
  timeout: 30
)
```

`api_key` defaults to `ENV["VECTORAMP_API_KEY"]`.

## Datasets

```ruby
# Paginated envelope: { "datasets" => [VectorAmp::Dataset, ...], "total" => n, "limit" => 50, "offset" => 0 }
page = client.datasets.list(limit: 50, offset: 0)
dataset = page["datasets"].first

# Object->method style (preferred).
dataset = client.datasets.get("dataset-uuid")
dataset.stats
dataset.search(
  "wireless headphones",
  top_k: 10,
  filters: { category: "electronics" },
  advanced_filters: [
    { field: "price", op: "lt", value: 100.0 }
  ],
  include_metadata: true,
  include_documents: false,
  rerank: true # expands to vectoramp / VectorAmp-Rerank-v1
)
dataset.insert(vectors: [{ id: "sku-1", values: [0.1, 0.2], metadata: { category: "electronics" } }])
dataset.add_texts(["Wireless headphones"], metadata: { category: "electronics" })
dataset.ask("Which headphones should I buy?")
dataset.ingest_source("source-uuid")
dataset.delete

# Hybrid search: pass a sparse query and/or alpha weighting on a hybrid dataset.
dataset.search("wireless headphones", hybrid: true, sparse_query: "headphones", alpha: 0.5)

# Client-namespaced methods are equivalent and also supported.
client.datasets.stats("dataset-uuid")
client.datasets.search("dataset-uuid", "wireless headphones", top_k: 10)
client.datasets.insert("dataset-uuid", vectors: [])
```

`client.datasets.create` intentionally does not accept `index_type`; all datasets are created with SABLE.

### Source documents

Dataset document listing is cursor-based: pass `next_cursor` into the next request and do not assume offsets or totals. Downloads return retained original bytes and follow API/storage redirects.

```ruby
page = client.datasets.list_documents("dataset-uuid", limit: 50, cursor: nil, status: "ready")
page.fetch("documents").each do |doc|
  next unless doc["download_available"]

  bytes = client.datasets.download_document("dataset-uuid", doc.fetch("id"))
end

if page["next_cursor"]
  next_page = client.datasets.list_documents("dataset-uuid", cursor: page["next_cursor"])
end

# Resource-style helpers are available too.
dataset = client.datasets.get("dataset-uuid")
docs = dataset.list_documents(limit: 25)
raw = dataset.download_document(docs.fetch("documents").first.fetch("id"))
```

## Ingestion

```ruby
# Sources: paginated envelope { "sources" => [...], "total" => n, ... }
client.ingestion.list_sources(limit: 50, offset: 0)
client.ingestion.get_source("source-uuid")

# Typed builders cover the supported source_type values:
# "web", "s3", "gcs", "gdrive", "file_upload", "jira", and "confluence".
source = client.sources.create_web(
  start_urls: ["https://docs.example.com"],
  max_depth: 1,
  include_assets: true,
  max_assets_per_page: 5
)

s3_source = client.sources.create_s3(
  bucket: "vectoramp-docs",
  prefix: "public/"
)

gcs_source = client.sources.create_gcs(bucket: "vectoramp-docs-gcs", prefix: "public/")

jira_source = client.sources.create_jira(
  cloud_id: "atlassian-cloud-id",
  project_keys: ["ENG"],
  include_comments: true # default
)

confluence_source = client.sources.create_confluence(
  cloud_id: "atlassian-cloud-id",
  spaces: ["ENG"],
  username: "service-account@example.com",
  api_token: ENV["CONFLUENCE_API_TOKEN"]
)

gdrive_source = client.sources.create_google_drive(
  folder_ids: ["google-drive-folder-id"]
)

file_source = client.sources.create_file_upload

# You can still pass name: when you want control. If omitted, the SDK chooses
# a readable default from the URL, bucket, Google Drive id, or upload timestamp.

# GenericSource is an escape hatch for API-compatible source configs that are
# not modeled by a typed SDK helper yet.
generic_source = VectorAmp::GenericSource.new(
  source_type: "custom",
  name: "custom-source",
  config: { endpoint: "https://example.com/feed" }
)
client.sources.create(generic_source)

# The lower-level existing API is still supported.
source = client.ingestion.create_source(
  source_type: "web",
  name: "docs-site",
  config: { start_urls: ["https://docs.example.com"], max_depth: 1 }
)

job = client.ingestion.start_job(
  source_id: source["id"],
  dataset_id: "dataset-uuid"
)

# Dataset resources can ingest by source id or by a typed source object that has an id.
dataset.ingest_source(source["id"])
typed_source = VectorAmp::WebSource.new(id: source["id"], name: "docs-site", start_urls: ["https://docs.example.com"])
dataset.ingest_source(typed_source)

# Jobs: paginated envelope { "jobs" => [...], "total" => n, ... }
client.ingestion.list_jobs(dataset_id: "dataset-uuid", limit: 50, offset: 0)
client.ingestion.get_job(job["job_id"])
client.ingestion.job_files(job["job_id"])
client.ingestion.job_statistics(job["job_id"])
client.ingestion.cancel_job(job["job_id"])
```

### Upload files from the filesystem

`ingest_files` uses the REST upload flow: create a `file_upload` source, initialize upload, PUT bytes to presigned URLs, then complete the upload.

```ruby
client.ingestion.ingest_files(
  dataset_id: "dataset-uuid",
  paths: ["docs/whitepaper.pdf", "docs/notes.md"],
  metadata: { team: "product" }
)

# Or from a Dataset resource. No source name is required; the SDK creates a
# file_upload source with a generated name before uploading.
dataset.ingest_files(paths: ["docs/whitepaper.pdf"])
```

## Intelligence / RAG

Non-streaming:

```ruby
answer = client.ask(
  "What are the key features?",
  dataset_id: "all",
  top_k: 5
)
puts answer["answer"]
```

Multi-turn conversations: the Intelligence API is stateless, so send prior turns
in `conversation_history`. You decide how many previous messages to include.

```ruby
history = [
  { role: "user", content: "What are the key features?" },
  { role: "assistant", content: "Hybrid search, reranking, and managed ingestion." }
]

follow_up = client.intelligence.query(
  "Which of those help with relevance?",
  dataset_id: "all",
  conversation_history: history.last(10) # include as many prior turns as you want
)
puts follow_up["answer"]
```

Streaming SSE:

```ruby
client.ask_stream("Summarize the docs", dataset_id: "dataset-uuid") do |event|
  print event["content"] if event["chunk_type"] == "text"
end

# Or as an Enumerator:
client.ask_stream("Summarize").each do |event|
  puts event.inspect
end
```

### Sessions

Persist multi-turn conversations server-side instead of resending history.

```ruby
session = client.intelligence.create_session(title: "Onboarding", dataset_id: "dataset-uuid")

client.intelligence.append_message(session.fetch("id"), role: "user", content: "What is SABLE?")
client.intelligence.append_message(session.fetch("id"), role: "assistant", content: "A managed index type.")

messages = client.intelligence.list_messages(session.fetch("id"))
sessions = client.intelligence.list_sessions(limit: 20)
client.intelligence.get_session(session.fetch("id"))
client.intelligence.delete_session(session.fetch("id"))
```

## Error handling

Non-2xx responses raise `VectorAmp::APIError` with `status`, `body`, and `headers`.

```ruby
begin
  client.datasets.get("missing")
rescue VectorAmp::APIError => e
  warn "VectorAmp API error #{e.status}: #{e.message}"
end
```

## Development

```bash
bundle install
bundle exec rake test
```

Tests mock HTTP with WebMock and enforce SimpleCov coverage.

## Method reference

Both access styles work everywhere: `client.datasets.<m>(id, ...)` and the
equivalent `datasetObj.<m>(...)` on a returned `VectorAmp::Dataset`.

### Datasets — `client.datasets`

| Method | Required | Optional (defaults) |
|---|---|---|
| `create(name:)` | `name` | `dim` (inferred), `embedding` (vectoramp/VectorAmp-Embedding-4B), `metric` ("cosine"), `hybrid`, `filters`, `metadata_schema`, `tuning`, `metadata` |
| `list` | — | `limit` (50), `offset` (0) |
| `get(id)` | `id` | — |
| `delete(id)` | `id` | — |
| `stats(id)` | `id` | — |
| `search(id, query = nil)` | `id` | `query`/`query_text`/`search_text`, `top_k` (10), `filters`, `advanced_filters`, `hybrid`, `sparse_query`, `alpha`, `rerank`, `include_documents`, `include_metadata`, `include_embeddings`, `embedding_model`, `embedding_provider`, `nprobe_override`, `rerank_depth_override` |
| `insert(id, vectors:)` | `id`, `vectors` | — (integer ids preserved as numbers) |
| `embed(id)` | `id` | `text`, `texts` (one required) |
| `add_texts(id, texts = nil)` | `id`, `texts` | `ids` (auto-generated), `metadata` |
| `list_documents(id)` | `id` | `limit` (50), `cursor`, `status` |
| `download_document(id, document_id)` | `id`, `document_id` | — |

Dataset-object helpers: `search`, `insert`, `add_texts`, `embed`, `delete`, `stats`,
`list_documents`, `download_document`, `ask`, `ingest_source`, `ingest_files`.

### Intelligence — `client.intelligence` (and `client.ask` / `client.ask_stream`)

| Method | Required | Optional (defaults) |
|---|---|---|
| `query(query)` / `ask` / `ask_stream` | `query` | `dataset_id` ("all" when unscoped), `top_k` (5 server-side), `conversation_history`, `include_sources`, `stream` |
| `create_session` | — | `title`, `dataset_id`, `workspace_id`, `metadata` |
| `list_sessions` | — | `limit` (50) |
| `get_session(session_id)` | `session_id` | — |
| `delete_session(session_id)` | `session_id` | — |
| `append_message(session_id, role:, content:)` | `session_id`, `role`, `content` | `metadata` |
| `list_messages(session_id)` | `session_id` | `limit` (100) |

### Sources — `client.sources` (alias of `client.ingestion`)

`create(source)`, `create_web(start_urls:)`, `create_s3(bucket:)`, `create_gcs(bucket:)`,
`create_google_drive(folder_ids:|file_ids:)`, `create_jira(cloud_id:)`,
`create_confluence(cloud_id:|base_url:)`, `create_file_upload`, `list_sources`, `get_source(id)`.
Jobs: `start_job(source_id:, dataset_id:)`, `list_jobs`, `get_job(id)`, `retry_job(id)`,
`ingest_files(dataset_id:, paths:)`.

### Schedules — `client.schedules`

`list`, `get(id)`, `create(source_id:, dataset_id:, cron:)`, `update(id)`, `delete(id)`, `trigger(id)`.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
