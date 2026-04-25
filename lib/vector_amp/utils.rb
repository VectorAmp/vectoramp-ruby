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
  end
end
