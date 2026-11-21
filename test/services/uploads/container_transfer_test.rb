# frozen_string_literal: true

require "test_helper"

module Uploads
  class ContainerTransferTest < ActiveSupport::TestCase
    include CheckpointStorageHelper

    teardown { restore_checkpoint_storage }

    test "object storage signs the container's URLs itself" do
      use_checkpoint_storage
      file = SessionCheckpointUploader.uploaded_file(id: "a.tar.gz", storage: :store)

      assert_equal "https://bucket.test/cache/b.tar.gz",
                   ContainerTransfer.put_url(SessionCheckpointUploader, :cache, "b.tar.gz", expires_in: 60, host: "web:4000")
      assert_equal "https://bucket.test/store/a.tar.gz", ContainerTransfer.get_url(file, expires_in: 60, host: "web:4000")
    end

    test "storage that cannot sign gets the session's callback address, with a token for that object" do
      url = ContainerTransfer.put_url(SessionCheckpointUploader, :cache, "b.tar.gz", expires_in: 60, host: "web:4000")

      assert url.start_with?("http://web:4000/agents/storage?token=")
      target = ContainerTransfer.resolve(Rack::Utils.parse_query(URI(url).query)["token"], method: "put")
      assert_equal [ SessionCheckpointUploader, :cache, "b.tar.gz" ], [ target.uploader, target.storage_key, target.id ]
    end
  end
end
