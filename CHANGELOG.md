# Changelog

All notable changes to this project will be documented in this file.

This project follows semantic versioning.

## [Unreleased]

### Changed

- **Breaking:** Intelligence queries now scope with `dataset_ids:` (an array) instead of the retired
  `dataset_id:`. `POST /intelligence/query` answers any request carrying the singular field with a
  400 naming the replacement, so `client.ask`, `client.ask_stream`,
  `client.intelligence.query` and `dataset.ask` all send `dataset_ids`. A stray `dataset_id:` is
  refused by the existing unknown-option guard with an `ArgumentError`.
- The `dataset_id: "all"` sentinel is retired. Omit `dataset_ids:` (or pass `nil`/`[]`) to search
  every dataset the API key can see. A bare string is accepted and wrapped.

## [0.4.0] - 2026-08-20

### Added

- Add `VectorAmp::GitHubSource` and `VectorAmp::GitLabSource` typed source builders.
- Add `client.sources.create_github(...)` and `client.sources.create_gitlab(...)`.

## [0.3.0] - 2026-07-20

### Added

- Add typed metadata-schema fields when creating datasets.
- Add metadata-schema merge/patch and full replacement operations.
- Document create, merge, and replace schema workflows.

## [0.2.0] - 2026-07-14

### Added

- Add dataset vector deletion helpers on client and dataset resources.
- Add organization secret helpers for OpenAI embedding API keys.
- Add OpenAI API key + dataset creation convenience helper.

## [0.1.0] - 2026-07-02

### Added

- Initial public-ready package baseline for VectorAmp SDK/CLI migration to GitHub.
- GitHub Actions CI workflow.
