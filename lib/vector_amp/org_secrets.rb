# frozen_string_literal: true

require "uri"

require_relative "utils"

module VectorAmp
  # Organization-scoped secret helpers exposed by the public API.
  class OrgSecretsResource
    DEFAULT_OPENAI_SECRET_REF = "emb:openai:api_key"

    # @param transport [#request] API transport.
    # @return [OrgSecretsResource]
    def initialize(transport)
      @transport = transport
    end

    # Store or update an organization secret by name.
    # @param name [String] org secret reference to write.
    # @param value [String] plaintext value sent once to the API.
    def put(name:, value:)
      secret_name = name.to_s.strip
      secret_value = value.to_s.strip
      raise ArgumentError, "name is required" if secret_name.empty?
      raise ArgumentError, "value is required" if secret_value.empty?

      @transport.request(:put, "/org-secrets/#{URI.encode_www_form_component(secret_name)}", body: { value: secret_value })
    end

    # Check whether an organization secret exists.
    def exists?(name:)
      secret_name = name.to_s.strip
      raise ArgumentError, "name is required" if secret_name.empty?
      @transport.request(:get, "/org-secrets/#{URI.encode_www_form_component(secret_name)}")
    end

    # Store or update the organization OpenAI API key.
    # @param api_key [String] OpenAI API key to store server-side.
    # @param secret_ref [String] org secret reference to write.
    # @param validate [Boolean] accepted for API compatibility; generic org-secret writes do not validate.
    # @param model [String, nil] accepted for API compatibility.
    # @return [Hash, nil] API response; normally nil/empty for 204.
    def put_openai_api_key(api_key:, secret_ref: DEFAULT_OPENAI_SECRET_REF, validate: false, model: nil)
      key = api_key.to_s.strip
      raise ArgumentError, "api_key is required" if key.empty?

      put(name: secret_ref, value: key)
    end

    alias update_openai_api_key put_openai_api_key

    # Check whether the default organization OpenAI API key exists.
    # @return [Hash, nil] API response; normally nil/empty for 204.
    def openai_api_key?
      exists?(name: DEFAULT_OPENAI_SECRET_REF)
    end
  end
end
