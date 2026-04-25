# VectorAmp Ruby SDK

Official Ruby client for the VectorAmp API.

- Default API: `https://api.vectoramp.com`
- Auth: `X-API-Key`
- Transport abstraction: REST today, designed so gRPC can be added later
- Public/RubyGems-ready gem structure. This repository is not published by CI.

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

client = VectorAmp::Client.new(api_key: ENV.fetch("VECTORAMP_API_KEY"))

# Create a SABLE dataset. The SDK always sends index_type: "sable" and does
# not expose index type selection.
dataset = client.datasets.create(
  name: "product-docs",
  dim: 2560,
  metric: "cosine",
  embedding: {
    provider: "vectoramp",
    model: "Qwen/Qwen3-Embedding-4B"
  }
)

# Create/get/list return VectorAmp::Dataset resources, so you can use instance methods.
# Add raw vectors.
dataset.insert(vectors: [
  {
    id: "doc-001",
    values: [0.1, 0.2, 0.3],
    metadata: { title: "Intro", source: "manual" }
  }
])

# Or embed and insert text in one call.
dataset.add_texts(
  texts: ["VectorAmp is powered by SABLE."],
  metadata: { source: "readme" }
)

results = dataset.search(
  "What powers VectorAmp?",
  top_k: 5,
  include_documents: true
)

answer = dataset.ask("What powers VectorAmp?")
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

# Resource-style methods.
dataset = client.datasets.get("dataset-uuid")
dataset.stats
dataset.search(
  query_text: "wireless headphones",
  top_k: 10,
  filters: { category: "electronics" },
  advanced_filters: [
    { field: "price", op: "lt", value: 100.0 }
  ],
  include_metadata: true,
  include_documents: false
)
dataset.insert(vectors: [{ id: "sku-1", values: [0.1, 0.2], metadata: { category: "electronics" } }])
dataset.add_texts(["Wireless headphones"], metadata: { category: "electronics" })
dataset.ask("Which headphones should I buy?")
dataset.ingest_source("source-uuid")
dataset.delete

# Service-style methods are still supported.
client.datasets.stats("dataset-uuid")
client.datasets.delete("dataset-uuid")
client.datasets.search("dataset-uuid", "wireless headphones", top_k: 10)
client.datasets.insert("dataset-uuid", vectors: [])
```

`client.datasets.create` intentionally does not accept `index_type`; all datasets are created with SABLE.

## Ingestion

```ruby
# Sources: paginated envelope { "sources" => [...], "total" => n, ... }
client.ingestion.list_sources(limit: 50, offset: 0)
client.ingestion.get_source("source-uuid")

# Typed builders cover the supported source_type values:
# "web", "s3", "gdrive", and "file_upload".
source = client.sources.create_web(
  start_urls: ["https://docs.example.com"],
  max_depth: 1
)

s3_source = client.sources.create_s3(
  bucket: "vectoramp-docs",
  prefix: "public/"
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

## Release status

This gem is structured for RubyGems but is not published from this repository yet.
