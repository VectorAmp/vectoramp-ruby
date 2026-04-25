# frozen_string_literal: true

module VectorAmp
  module Transport
    class Base
      def request(method, path, query: nil, body: nil, headers: {}, stream: false, &block)
        raise NotImplementedError, "transport must implement #request"
      end
    end
  end
end
