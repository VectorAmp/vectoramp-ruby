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

# Add raw vectors.
client.datasets.insert(dataset["id"], vectors: [
  {
    id: "doc-001",
    values: [0.1, 0.2, 0.3],
    metadata: { title: "Intro", source: "manual" }
  }
])

# Or embed and insert text in one call.
client.datasets.add_texts(
  dataset["id"],
  texts: ["VectorAmp is powered by SABLE."],
  metadata: { source: "readme" }
)

results = client.datasets.search(
  dataset["id"],
  query_text: "What powers VectorAmp?",
  top_k: 5,
  include_documents: true
)
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
# Paginated envelope: { "datasets" => [...], "total" => n, "limit" => 50, "offset" => 0 }
client.datasets.list(limit: 50, offset: 0)

client.datasets.get("dataset-uuid")
client.datasets.stats("dataset-uuid")
client.datasets.delete("dataset-uuid")

client.datasets.search(
  "dataset-uuid",
  query_text: "wireless headphones",
  top_k: 10,
  filters: { category: "electronics" },
  advanced_filters: [
    { field: "price", op: "lt", value: 100.0 }
  ],
  include_metadata: true,
  include_documents: false
)
```

`client.datasets.create` intentionally does not accept `index_type`; all datasets are created with SABLE.

## Ingestion

```ruby
# Sources: paginated envelope { "sources" => [...], "total" => n, ... }
client.ingestion.list_sources(limit: 50, offset: 0)
client.ingestion.get_source("source-uuid")

source = client.ingestion.create_source(
  source_type: "web",
  name: "docs-site",
  config: { start_urls: ["https://docs.example.com"], max_depth: 1 }
)

job = client.ingestion.start_job(
  source_id: source["id"],
  dataset_id: "dataset-uuid"
)

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
  source_name: "product-docs-upload",
  metadata: { team: "product" }
)
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
