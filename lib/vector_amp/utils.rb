# frozen_string_literal: true

module VectorAmp
  module Utils
    module_function

    def compact_hash(hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key] = value unless value.nil?
      end
    end

    def ensure_no_unknown!(unknown, method_name)
      return if unknown.empty?

      keys = unknown.keys.map(&:to_s).join(", ")
      raise ArgumentError, "unknown #{method_name} option(s): #{keys}"
    end

    # Coerce a vector record id into a JSON-safe value that preserves numeric ids.
    #
    # Integers (and integer-valued floats) are returned as Integers so they
    # serialize as JSON numbers rather than strings. Everything else is left as
    # given (strings stay strings). This prevents the API from rewriting numeric
    # ids that were sent as quoted strings.
    # @param id [Object] vector id.
    # @return [Object] the id, with numeric ids preserved as numbers.
    def coerce_vector_id(id)
      case id
      when Integer then id
      when Float then id == id.to_i ? id.to_i : id
      else id
      end
    end

    # Normalize a list of vector records so numeric ids stay numeric.
    # @param vectors [Array<Hash>] vector records.
    # @return [Array<Hash>] records with id values coerced via {coerce_vector_id}.
    def normalize_vectors(vectors)
      Array(vectors).map do |vector|
        next vector unless vector.is_a?(Hash)
        next vector unless vector.key?(:id) || vector.key?("id")

        copy = vector.dup
        if copy.key?(:id)
          copy[:id] = coerce_vector_id(copy[:id])
        else
          copy["id"] = coerce_vector_id(copy["id"])
        end
        copy
      end
    end
  end
end
