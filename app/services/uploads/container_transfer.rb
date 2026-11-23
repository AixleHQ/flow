# frozen_string_literal: true

module Uploads
  # The URLs an agent container moves a file into or out of Shrine storage with, so the
  # bytes never pass through a Temporal worker. Object storage signs them itself. A
  # storage that cannot (FileSystem in development, Memory in tests) gets a short-lived
  # token instead, for one object and one method, served by ContainerStorageController
  # at `host`: the session's `:container_assets` callback address, the one stored files
  # are downloaded from (ContainerRuntime::CallbackUrls).
  module ContainerTransfer
    # A token can only name one of these, so it can only ever reach their storages.
    UPLOADERS = %w[SessionCheckpointUploader].freeze
    PURPOSE = "container_storage_transfer"

    Target = Data.define(:uploader, :storage_key, :id) do
      def storage = uploader.storages[storage_key]
    end

    module_function

    def put_url(uploader, storage_key, id, expires_in:, host:)
      storage = uploader.storages.fetch(storage_key)
      return storage.presign(id, method: :put, expires_in: expires_in.to_i)[:url] if signs?(storage)

      app_url(uploader, storage_key, id, "put", expires_in, host)
    end

    def get_url(file, expires_in:, host:)
      return file.url(expires_in: expires_in.to_i) if signs?(file.storage)

      app_url(file.shrine_class, file.storage_key, file.id, "get", expires_in, host)
    end

    # The object a token grants `method` on, or nil. Nil too where the storage signs its
    # own URLs: the app never stands in for object storage.
    def resolve(token, method:)
      data = verifier.verified(token.to_s, purpose: PURPOSE)
      return nil unless data.is_a?(Hash) && data["method"] == method && UPLOADERS.include?(data["uploader"])

      target = Target.new(uploader: data["uploader"].constantize, storage_key: data["storage"].to_sym, id: data["id"].to_s)
      target.storage && !signs?(target.storage) ? target : nil
    end

    def signs?(storage) = storage.respond_to?(:presign)

    def app_url(uploader, storage_key, id, method, expires_in, host)
      token = verifier.generate({ "uploader" => uploader.name, "storage" => storage_key.to_s, "id" => id, "method" => method },
                                expires_in: expires_in, purpose: PURPOSE)
      ContainerAssetUrl.call("http://app/agents/storage?#{{ token: token }.to_query}", host: host)
    end

    def verifier = Rails.application.message_verifier(PURPOSE)
  end
end
