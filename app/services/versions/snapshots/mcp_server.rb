# frozen_string_literal: true

module Versions
  module Snapshots
    # Header and env VALUES are credentials and never enter a snapshot: history
    # would multiply copies, keep a token alive after it was revoked, and a
    # revert would resurrect it. The snapshot keeps each key with a keyed HMAC of
    # its value — enough for a diff to say "TOKEN changed" and nothing more.
    #
    # A revert therefore leaves the current values alone. When it moves the
    # server to another destination, MCPServer#forget_secrets_for_new_destination
    # drops them (and the OAuth connections) exactly as an edit would; supplying
    # the current values during a revert would turn it into a way of sending
    # them somewhere else, so it never does.
    class MCPServer < Base
      FIELDS = %w[name description transport url command args auth_type credential_scope enabled kind
                  connector_name connector_version connector_manifest].freeze
      EXCLUDED = %w[id scope_type scope_id project_id company_id encrypted_env encrypted_headers env headers
                    tool_snapshot tool_drift tool_snapshot_at archived_at current_version_number
                    created_at updated_at].freeze
      SECRET_FIELDS = %w[env headers].freeze

      class << self
        def dump(record)
          super.merge("secrets" => SECRET_FIELDS.to_h { |field| [ field, fingerprints(record, field) ] })
        end

        def fingerprint(record, field, key, value)
          digest = OpenSSL::HMAC.hexdigest("SHA256", secret_key, "#{record.id}:#{field}:#{key}:#{value}")
          "hmac:#{digest.first(16)}"
        end

        private

        def fingerprints(record, field)
          record.public_send(field).sort.to_h { |key, value| [ key, fingerprint(record, field, key, value) ] }
        end

        def secret_key
          @secret_key ||= Rails.application.key_generator.generate_key("entity_versions/mcp_secret_fingerprint", 32)
        end
      end
    end
  end
end
