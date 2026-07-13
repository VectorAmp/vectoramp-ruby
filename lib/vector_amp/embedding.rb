# frozen_string_literal: true

require_relative "utils"

module VectorAmp
  # Embedding configuration defaults and helpers.
  #
  # SDK callers rarely need to specify an embedding model. By default datasets use
  # the managed VectorAmp embedding model and the SDK infers the vector dimension.
  module Embedding
    module_function

    # Default embedding provider used when none is supplied.
    DEFAULT_PROVIDER = "vectoramp"
    # Default embedding model used when none is supplied.
    DEFAULT_MODEL = "VectorAmp-Embedding-4B"

    # Built-in dimension inference for known provider/model pairs.
    DIM_TABLE = {
      ["vectoramp", "VectorAmp-Embedding-4B"] => 2560,
      ["openai", "text-embedding-3-small"] => 1536,
      ["openai", "text-embedding-3-large"] => 3072,
    }.freeze

    # The fully managed default embedding configuration.
    # @return [Hash] `{ provider:, model: }`
    def default_embedding
      { provider: DEFAULT_PROVIDER, model: DEFAULT_MODEL }
    end

    # Build an OpenAI embedding configuration.
    # @param size [String, Symbol] `"small"` (text-embedding-3-small) or `"large"` (text-embedding-3-large).
    # @param secret_ref [String, nil] organization secret reference containing the OpenAI API key.
    # @return [Hash] `{ provider: "openai", model: ..., secret_ref: ... }`
    # @raise [ArgumentError] when size is not "small" or "large".
    def openai(size = "small", secret_ref: "emb:openai:api_key")
      model = case size.to_s
              when "small" then "text-embedding-3-small"
              when "large" then "text-embedding-3-large"
              else
                raise ArgumentError, %(openai size must be "small" or "large", got #{size.inspect})
              end
      Utils.compact_hash(provider: "openai", model: model, secret_ref: secret_ref)
    end

    # Normalize a user-supplied embedding value into a config hash.
    # Accepts a Hash (`{ provider:, model:, secret_ref? }`) or a String model name
    # (assumed to use the default provider).
    # @param embedding [Hash, String, nil]
    # @return [Hash] normalized embedding config with string keys for provider/model lookups.
    def normalize(embedding)
      case embedding
      when nil then default_embedding
      when String then { provider: DEFAULT_PROVIDER, model: embedding }
      when Hash then embedding
      else
        raise ArgumentError, "embedding must be a Hash or String"
      end
    end

    # Infer the vector dimension for an embedding config, or nil when unknown.
    # @param embedding [Hash] normalized embedding config.
    # @return [Integer, nil] inferred dimension or nil for custom/unknown models.
    def infer_dim(embedding)
      provider = embedding[:provider] || embedding["provider"]
      model = embedding[:model] || embedding["model"]
      DIM_TABLE[[provider.to_s, model.to_s]]
    end
  end
end
