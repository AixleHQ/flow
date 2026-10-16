# frozen_string_literal: true

module Bitbucket
  module Forge
    # Forge spells one identifier several ways: an ARI in the invocation token
    # (`ari:cloud:ecosystem::environment/<id>`), a bare id in lifecycle payloads,
    # a UUID with or without braces for a workspace. Comparisons go through here.
    module Ids
      module_function

      # The last path segment of an ARI, or the value itself.
      def tail(value) = value.to_s.strip.split("/").last.to_s

      # A UUID in Bitbucket REST's own form, `{lowercase-uuid}`, or nil.
      def uuid(value)
        bare = value.to_s.strip.delete_prefix("{").delete_suffix("}").downcase
        bare.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/) ? "{#{bare}}" : nil
      end

      def same?(a, b) = a.present? && b.present? && tail(a) == tail(b)
    end
  end
end
