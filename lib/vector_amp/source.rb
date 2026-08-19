# frozen_string_literal: true

require "uri"
require_relative "utils"

module VectorAmp
  # Base value object for ingestion source definitions.
  #
  # Source objects can be passed to `client.sources.create_source(source)` to
  # create a source or to `dataset.ingest_source(source)` once they include an id
  # returned by the API.
  class Source
    SUPPORTED_SOURCE_TYPES = %w[s3 web gcs gdrive file_upload jira confluence github gitlab].freeze

    # @return [String, nil] API source id when returned by the API.
    # @return [String] source type (`s3`, `web`, `gdrive`, or `file_upload`).
    # @return [String] source display name.
    # @return [String, nil] optional source description.
    # @return [Hash] source-specific configuration.
    # @return [Hash, nil] optional source metadata.
    attr_reader :id, :source_type, :name, :description, :config, :metadata

    # Create a source value object.
    # @param source_type [String, Symbol] one of `s3`, `web`, `gdrive`, or `file_upload`.
    # @param name [String] source display name.
    # @param config [Hash] source-specific config sent to the API.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param id [String, nil] optional API source id.
    # @return [Source]
    def initialize(source_type:, name:, config:, description: nil, metadata: nil, id: nil)
      raise ArgumentError, "source_type is required" if source_type.nil? || source_type.to_s.empty?
      raise ArgumentError, "name is required" if name.nil? || name.to_s.empty?
      raise ArgumentError, "config must be a Hash" unless config.is_a?(Hash)

      @id = id
      @source_type = source_type.to_s
      @name = name.to_s
      @description = description
      @config = config
      @metadata = metadata
    end

    # Build a generic source object from an API response hash.
    # @param data [Hash] source payload returned by the API.
    # @return [GenericSource]
    def self.from_api(data)
      hash = normalize_hash(data)
      GenericSource.new(
        id: hash["id"],
        source_type: hash.fetch("source_type"),
        name: hash.fetch("name"),
        description: hash["description"],
        config: hash.fetch("config", {}),
        metadata: hash["metadata"]
      )
    end

    # Read a source attribute by string or symbol key.
    # @param key [String, Symbol] attribute name.
    # @return [Object, nil]
    def [](key)
      to_h[key.to_sym] || to_h[key.to_s]
    end

    # Convert this source to a hash including the id when present.
    # @return [Hash]
    def to_h
      Utils.compact_hash(
        id: id,
        source_type: source_type,
        name: name,
        description: description,
        config: config,
        metadata: metadata
      )
    end
    alias to_hash to_h

    # Convert this source to an API create-source request body.
    # @return [Hash]
    def to_create_body
      Utils.compact_hash(
        source_type: source_type,
        name: name,
        description: description,
        config: config,
        metadata: metadata
      )
    end

    def inspect
      "#<#{self.class} id=#{id.inspect} source_type=#{source_type.inspect} name=#{name.inspect}>"
    end

    def self.normalize_hash(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), memo| memo[key.to_s] = item }
      else
        {}
      end
    end
  end

  # Default source-name helpers used when a name is omitted.
  module SourceNames
    module_function

    # @return [String] timestamped `ruby-sdk-file-upload-YYYYmmddHHMMSS` name.
    def file_upload(now: Time.now.utc)
      "ruby-sdk-file-upload-#{now.strftime("%Y%m%d%H%M%S")}"
    end

    # @param start_urls [String, Array<String>] source URLs.
    # @return [String] `web-<host>` from the first URL, or `web-source`.
    def web(start_urls)
      first_url = Array(start_urls).first.to_s
      host = URI.parse(first_url).host
      host && !host.empty? ? "web-#{host}" : "web-source"
    rescue URI::InvalidURIError
      "web-source"
    end

    # @param bucket [String] bucket name.
    # @param prefix [String, nil] optional prefix.
    # @return [String] `s3-<bucket>` or `s3-<bucket>-<prefix>`.
    def s3(bucket, prefix = nil)
      parts = ["s3", bucket.to_s, prefix.to_s.delete_suffix("/")].reject(&:empty?)
      parts.join("-")
    end

    def gcs(bucket, prefix = nil)
      parts = ["gcs", bucket.to_s, prefix.to_s.delete_suffix("/")].reject(&:empty?)
      parts.join("-")
    end

    def jira(project_keys: nil, cloud_id: nil)
      key = Array(project_keys).first || cloud_id
      key ? "jira-#{key}" : "jira-source"
    end

    # @param spaces [String, Array<String>, nil] Confluence space keys.
    # @param cloud_id [String, nil] Atlassian cloud/site id.
    # @param base_url [String, nil] Confluence base URL, e.g. https://company.atlassian.net.
    # @return [String] `confluence-<space>`, `confluence-<host>`, or `confluence-source`.
    def confluence(spaces: nil, cloud_id: nil, base_url: nil)
      space = Array(spaces).first
      return "confluence-#{space}" if space

      host = host_from_url(base_url)
      return "confluence-#{host}" if host
      return "confluence-#{cloud_id}" if cloud_id

      "confluence-source"
    end

    def host_from_url(url)
      return nil if url.nil? || url.to_s.empty?

      host = URI.parse(url.to_s).host
      host && !host.empty? ? host : nil
    rescue URI::InvalidURIError
      nil
    end

    # @param repositories [String, Array<String>, nil] `owner/repo` full names.
    # @return [String] `github-<owner>-<repo>` from the first repository, or `github-source`.
    def github(repositories: nil)
      repository = Array(repositories).first
      repository ? "github-#{slugify(repository)}" : "github-source"
    end

    # @param projects [String, Array<String>, nil] project paths with namespace.
    # @param groups [String, Array<String>, nil] group paths.
    # @return [String] `gitlab-<path>` from the first project or group, or `gitlab-source`.
    def gitlab(projects: nil, groups: nil)
      path = Array(projects).first || Array(groups).first
      path ? "gitlab-#{slugify(path)}" : "gitlab-source"
    end

    # Lowercase a repository/group path into a dash-separated name fragment.
    # @param value [String] path such as `owner/repo` or `group/subgroup/project`.
    # @return [String]
    def slugify(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    end

    # @param folder_ids [String, Array<String>, nil] folder ids.
    # @param file_ids [String, Array<String>, nil] file ids.
    # @return [String] `google-drive-<first id>` or `google-drive-source`.
    def google_drive(folder_ids: nil, file_ids: nil)
      first_folder = Array(folder_ids).first
      first_file = Array(file_ids).first
      suffix = first_folder || first_file
      suffix ? "google-drive-#{suffix}" : "google-drive-source"
    end
  end

  # Web-crawl ingestion source.
  class WebSource < Source
    # @param start_urls [String, Array<String>] required seed URLs.
    # @param name [String, nil] defaults to `web-<host>` from the first URL, or `web-source`.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param id [String, nil] optional API source id.
    # @param config [Hash] additional web-source config forwarded to the API.
    # @return [WebSource]
    def initialize(start_urls:, name: nil, description: nil, metadata: nil, id: nil, **config)
      urls = Array(start_urls)
      raise ArgumentError, "start_urls must not be empty" if urls.empty?

      super(
        id: id,
        source_type: "web",
        name: name || SourceNames.web(urls),
        description: description,
        metadata: metadata,
        config: Utils.compact_hash(config.merge(start_urls: urls))
      )
    end
  end

  # S3 ingestion source.
  class S3Source < Source
    # @param bucket [String] required S3 bucket name.
    # @param name [String, nil] defaults to `s3-<bucket>` or `s3-<bucket>-<prefix>`.
    # @param prefix [String, nil] optional object prefix.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param id [String, nil] optional API source id.
    # @param config [Hash] additional S3-source config forwarded to the API.
    # @return [S3Source]
    def initialize(bucket:, name: nil, prefix: nil, description: nil, metadata: nil, id: nil, **config)
      raise ArgumentError, "bucket is required" if bucket.nil? || bucket.to_s.empty?

      super(
        id: id,
        source_type: "s3",
        name: name || SourceNames.s3(bucket, prefix),
        description: description,
        metadata: metadata,
        config: Utils.compact_hash(config.merge(bucket: bucket, prefix: prefix))
      )
    end
  end

  # Google Cloud Storage ingestion source.
  class GCSSource < Source
    def initialize(bucket:, name: nil, prefix: nil, connection_id: nil, description: nil, metadata: nil, id: nil, **config)
      raise ArgumentError, "bucket is required" if bucket.nil? || bucket.to_s.empty?

      super(
        id: id,
        source_type: "gcs",
        name: name || SourceNames.gcs(bucket, prefix),
        description: description,
        metadata: metadata,
        config: Utils.compact_hash(config.merge(bucket: bucket, prefix: prefix, connection_id: connection_id))
      )
    end
  end

  # Google Drive ingestion source.
  class GoogleDriveSource < Source
    # @param name [String, nil] defaults to `google-drive-<first id>` or `google-drive-source`.
    # @param folder_ids [String, Array<String>, nil] folder ids to ingest; required if file_ids is empty.
    # @param file_ids [String, Array<String>, nil] file ids to ingest; required if folder_ids is empty.
    # @param auth_mode [String, nil] auth strategy (`service_account`, `oauth`); omitted from config when nil.
    # @param service_account_json [Hash, String, nil] service-account credentials for `service_account` auth.
    # @param oauth_credentials [Hash, nil] OAuth credentials for `oauth` auth.
    # @param connection_id [String, nil] optional managed connection id used in place of inline credentials.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param id [String, nil] optional API source id.
    # @param config [Hash] additional Google Drive-source config forwarded to the API.
    # @return [GoogleDriveSource]
    def initialize(name: nil, folder_ids: nil, file_ids: nil, auth_mode: nil, service_account_json: nil,
                   oauth_credentials: nil, connection_id: nil, description: nil, metadata: nil, id: nil, **config)
      if Array(folder_ids).empty? && Array(file_ids).empty?
        raise ArgumentError, "folder_ids or file_ids is required"
      end

      super(
        id: id,
        source_type: "gdrive",
        name: name || SourceNames.google_drive(folder_ids: folder_ids, file_ids: file_ids),
        description: description,
        metadata: metadata,
        config: Utils.compact_hash(config.merge(
          folder_ids: folder_ids,
          file_ids: file_ids,
          auth_mode: auth_mode,
          service_account_json: service_account_json,
          oauth_credentials: oauth_credentials,
          connection_id: connection_id
        ))
      )
    end
  end

  # File-upload ingestion source used by direct local file uploads.
  class FileUploadSource < Source
    # @param name [String, nil] defaults to timestamped `ruby-sdk-file-upload-YYYYmmddHHMMSS`.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param id [String, nil] optional API source id.
    # @param storage_provider [String] storage backend; defaults to `s3`.
    # @param sync_mode [String] sync strategy; defaults to `full`.
    # @param config [Hash] additional file-upload config forwarded to the API.
    # @return [FileUploadSource]
    def initialize(name: nil, description: nil, metadata: nil, id: nil, storage_provider: "s3", sync_mode: "full", **config)
      super(
        id: id,
        source_type: "file_upload",
        name: name || SourceNames.file_upload,
        description: description,
        metadata: metadata,
        config: Utils.compact_hash(config.merge(storage_provider: storage_provider, sync_mode: sync_mode))
      )
    end
  end

  # Jira ingestion source. include_comments defaults to true.
  class JiraSource < Source
    def initialize(cloud_id:, name: nil, access_token: nil, project_keys: nil, jql: nil, include_comments: true, connection_id: nil, description: nil, metadata: nil, id: nil, **config)
      raise ArgumentError, "cloud_id is required" if cloud_id.nil? || cloud_id.to_s.empty?

      super(
        id: id,
        source_type: "jira",
        name: name || SourceNames.jira(project_keys: project_keys, cloud_id: cloud_id),
        description: description,
        metadata: metadata,
        config: Utils.compact_hash(config.merge(cloud_id: cloud_id, access_token: access_token, project_keys: project_keys, jql: jql, include_comments: include_comments, connection_id: connection_id))
      )
    end
  end

  # Confluence ingestion source. Authenticates via basic auth (username + API
  # token) by default, or Atlassian OAuth. include_attachments defaults to false.
  class ConfluenceSource < Source
    # @param cloud_id [String, nil] Atlassian OAuth cloud/site id; required unless base_url is given.
    # @param base_url [String, nil] Confluence base URL, e.g. https://company.atlassian.net.
    # @param name [String, nil] defaults to `confluence-<space>`/`confluence-<host>`/`confluence-source`.
    # @param auth_mode [String] `basic` (default) or `oauth`.
    # @param username [String, nil] username for basic auth.
    # @param api_token [String, nil] API token for basic auth.
    # @param oauth_credentials [Hash, nil] OAuth credentials for oauth auth_mode.
    # @param spaces [String, Array<String>, nil] space keys to ingest; empty means all accessible.
    # @param include_attachments [Boolean] include page attachments; defaults to false.
    # @param connection_id [String, nil] optional managed connection id used in place of inline credentials.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param id [String, nil] optional API source id.
    # @param config [Hash] additional Confluence-source config forwarded to the API.
    # @return [ConfluenceSource]
    def initialize(cloud_id: nil, base_url: nil, name: nil, auth_mode: "basic", username: nil, api_token: nil,
                   oauth_credentials: nil, spaces: nil, include_attachments: false, connection_id: nil, description: nil, metadata: nil, id: nil, **config)
      if (cloud_id.nil? || cloud_id.to_s.empty?) && (base_url.nil? || base_url.to_s.empty?)
        raise ArgumentError, "cloud_id or base_url is required"
      end

      super(
        id: id,
        source_type: "confluence",
        name: name || SourceNames.confluence(spaces: spaces, cloud_id: cloud_id, base_url: base_url),
        description: description,
        metadata: metadata,
        config: Utils.compact_hash(config.merge(
          cloud_id: cloud_id,
          base_url: base_url,
          auth_mode: auth_mode,
          username: username,
          api_token: api_token,
          oauth_credentials: oauth_credentials,
          spaces: spaces.nil? ? nil : Array(spaces),
          include_attachments: include_attachments,
          connection_id: connection_id
        ))
      )
    end
  end

  # GitHub ingestion source backed by the VectorAmp GitHub App.
  #
  # Repositories, active branches, pull requests, and review discussions are read
  # through a GitHub App installation, so no token is passed to the SDK. Install
  # the VectorAmp GitHub App from the Sources page in the app first; the
  # installation id shown there is what this class needs.
  class GitHubSource < Source
    # @param installation_id [Integer] required GitHub App installation id; must be positive.
    # @param repositories [String, Array<String>] required `owner/repo` full names.
    # @param name [String, nil] defaults to `github-<owner>-<repo>` from the first repository.
    # @param ref_mode [String, nil] `active` (server default), `default`, or `explicit`.
    # @param refs [String, Array<String>, nil] explicit branch names for `ref_mode: "explicit"`.
    # @param excluded_refs [String, Array<String>, nil] branch names to skip.
    # @param active_branch_days [Integer, nil] activity window in days (1-90); server default 7.
    # @param include_pull_requests [Boolean, nil] ingest pull requests; server default true.
    # @param include_review_threads [Boolean, nil] ingest review discussions; server default true.
    # @param include_direct_commits [Boolean, nil] ingest commits outside a pull request; server default true.
    # @param include_globs [String, Array<String>, nil] path globs to include; server default `**/*`.
    # @param exclude_globs [String, Array<String>, nil] path globs to skip.
    # @param max_file_size_bytes [Integer, nil] per-file ceiling (1-25_000_000); server default 1_000_000.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param id [String, nil] optional API source id.
    # @param config [Hash] additional GitHub-source config forwarded to the API.
    # @return [GitHubSource]
    def initialize(installation_id:, repositories:, name: nil, ref_mode: nil, refs: nil, excluded_refs: nil,
                   active_branch_days: nil, include_pull_requests: nil, include_review_threads: nil,
                   include_direct_commits: nil, include_globs: nil, exclude_globs: nil, max_file_size_bytes: nil,
                   description: nil, metadata: nil, id: nil, **config)
      unless installation_id.is_a?(Integer) && installation_id.positive?
        raise ArgumentError, "installation_id must be a positive Integer"
      end

      repository_list = Array(repositories)
      raise ArgumentError, "repositories must not be empty" if repository_list.empty?

      super(
        id: id,
        source_type: "github",
        name: name || SourceNames.github(repositories: repository_list),
        description: description,
        metadata: metadata,
        config: Utils.compact_hash(config.merge(
          installation_id: installation_id,
          repositories: repository_list,
          ref_mode: ref_mode,
          refs: refs.nil? ? nil : Array(refs),
          excluded_refs: excluded_refs.nil? ? nil : Array(excluded_refs),
          active_branch_days: active_branch_days,
          include_pull_requests: include_pull_requests,
          include_review_threads: include_review_threads,
          include_direct_commits: include_direct_commits,
          include_globs: include_globs.nil? ? nil : Array(include_globs),
          exclude_globs: exclude_globs.nil? ? nil : Array(exclude_globs),
          max_file_size_bytes: max_file_size_bytes
        ))
      )
    end
  end

  # GitLab ingestion source for gitlab.com or a self-managed instance.
  #
  # Authenticates with an access token (`auth_mode: "token"` plus `access_token`)
  # or a stored OAuth connection (`connection_id`). At least one group or project
  # is required.
  class GitLabSource < Source
    # @param groups [String, Array<String>, nil] group paths; required unless projects is given.
    # @param projects [String, Array<String>, nil] project paths with namespace; required unless groups is given.
    # @param name [String, nil] defaults to `gitlab-<path>` from the first project or group.
    # @param auth_mode [String] `oauth` (default) or `token`.
    # @param gitlab_url [String] instance base URL; defaults to `https://gitlab.com`.
    # @param access_token [String, nil] personal or group access token for `auth_mode: "token"`.
    # @param connection_id [String, nil] optional stored OAuth connection id used instead of a token.
    # @param ref_mode [String, nil] `active` (server default), `default`, or `explicit`.
    # @param refs [String, Array<String>, nil] explicit branch names for `ref_mode: "explicit"`.
    # @param excluded_refs [String, Array<String>, nil] branch names to skip.
    # @param active_branch_days [Integer, nil] activity window in days (1-90); server default 7.
    # @param include_merge_requests [Boolean, nil] ingest merge requests; server default true.
    # @param include_review_threads [Boolean, nil] ingest review discussions; server default true.
    # @param include_direct_commits [Boolean, nil] ingest commits outside a merge request; server default true.
    # @param include_globs [String, Array<String>, nil] path globs to include; server default `**/*`.
    # @param exclude_globs [String, Array<String>, nil] path globs to skip.
    # @param max_file_size_bytes [Integer, nil] per-file ceiling (1-25_000_000); server default 1_000_000.
    # @param description [String, nil] optional description.
    # @param metadata [Hash, nil] optional metadata.
    # @param id [String, nil] optional API source id.
    # @param config [Hash] additional GitLab-source config forwarded to the API.
    # @return [GitLabSource]
    def initialize(groups: nil, projects: nil, name: nil, auth_mode: "oauth", gitlab_url: "https://gitlab.com",
                   access_token: nil, connection_id: nil, ref_mode: nil, refs: nil, excluded_refs: nil,
                   active_branch_days: nil, include_merge_requests: nil, include_review_threads: nil,
                   include_direct_commits: nil, include_globs: nil, exclude_globs: nil, max_file_size_bytes: nil,
                   description: nil, metadata: nil, id: nil, **config)
      group_list = Array(groups)
      project_list = Array(projects)
      if group_list.empty? && project_list.empty?
        raise ArgumentError, "groups or projects is required"
      end

      super(
        id: id,
        source_type: "gitlab",
        name: name || SourceNames.gitlab(projects: project_list, groups: group_list),
        description: description,
        metadata: metadata,
        config: Utils.compact_hash(config.merge(
          auth_mode: auth_mode,
          gitlab_url: gitlab_url,
          groups: group_list.empty? ? nil : group_list,
          projects: project_list.empty? ? nil : project_list,
          access_token: access_token,
          connection_id: connection_id,
          ref_mode: ref_mode,
          refs: refs.nil? ? nil : Array(refs),
          excluded_refs: excluded_refs.nil? ? nil : Array(excluded_refs),
          active_branch_days: active_branch_days,
          include_merge_requests: include_merge_requests,
          include_review_threads: include_review_threads,
          include_direct_commits: include_direct_commits,
          include_globs: include_globs.nil? ? nil : Array(include_globs),
          exclude_globs: exclude_globs.nil? ? nil : Array(exclude_globs),
          max_file_size_bytes: max_file_size_bytes
        ))
      )
    end
  end

  # Escape hatch for API-compatible source types/configs not yet modeled by the SDK.
  class GenericSource < Source
  end
end
