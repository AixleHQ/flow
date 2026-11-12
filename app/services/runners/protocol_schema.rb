# frozen_string_literal: true

module Runners
  # The JSON Schemas of the runner gateway's request bodies, the files in
  # runner/protocol/schemas/v1/ next to the protocol they belong to
  # (runner/protocol/PROTOCOL.md §5). The gateway checks a body against its
  # schema here, the way Templates::Package checks `template.yaml`:
  #
  #   Runners::ProtocolSchema.valid?("op_result.request", body)
  #
  # A new gateway endpoint that takes a body or parameters adds its schema to
  # that directory and names it in SCHEMAS.
  module ProtocolSchema
    DIRECTORY = Rails.root.join("runner/protocol/schemas/v1")
    SCHEMAS = %w[register.request check_in.request ops.query op_result.request releases.params].freeze

    class << self
      def valid?(name, document)
        schema(name).valid?(document)
      end

      def path(name)
        raise ArgumentError, "no runner protocol schema #{name.inspect}" unless SCHEMAS.include?(name)

        DIRECTORY.join("#{name}.json")
      end

      private

      # Read once per process. The schemas are part of the code, so a change
      # to one ships with a deploy.
      def schema(name)
        schemas.fetch(name) { raise ArgumentError, "no runner protocol schema #{name.inspect}" }
      end

      def schemas
        @schemas ||= SCHEMAS.index_with { |name| JSONSchemer.schema(JSON.parse(path(name).read)) }.freeze
      end
    end
  end
end
