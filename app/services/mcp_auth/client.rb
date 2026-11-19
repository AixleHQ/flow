# frozen_string_literal: true

module MCPAuth
  # The client asking for authorization, whichever way it identified itself.
  # `host` is set for a CIMD client only: the host its client_id URL is served
  # from, the one thing about it that is not self-asserted. `name` is whatever
  # the client calls itself.
  Client = Data.define(:client_id, :kind, :name, :host, :redirect_uris) do
    def self.resolve(client_id)
      raise InvalidClient, "The request names no client" if client_id.blank?
      return ClientMetadataDocument.fetch(client_id) if ClientMetadataDocument.url?(client_id)

      record = MCPAuthClient.find_by(client_id: client_id.to_s)
      raise InvalidClient, "This app is not registered with Aixle" if record.nil?

      record.note_use!
      new(client_id: record.client_id, kind: "dcr", name: record.client_name, host: nil,
          redirect_uris: record.redirect_uris)
    end

    def label
      return name.presence || "An unnamed app" if host.nil?

      name.present? ? "#{name} (#{host})" : host
    end
  end
end
