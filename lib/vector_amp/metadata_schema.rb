# frozen_string_literal: true

module VectorAmp
  # Helpers and canonical scalar types for dataset metadata schemas.
  module MetadataSchema
    STRING = "string"
    U32 = "u32"
    I32 = "i32"
    I64 = "i64"
    F32 = "f32"
    F64 = "f64"
    TYPES = [STRING, U32, I32, I64, F32, F64].freeze

    def self.field(name, type)
      raise ArgumentError, "unsupported metadata schema type: #{type.inspect}" unless TYPES.include?(type)

      { name: name.to_s, type: type }
    end
  end
end
