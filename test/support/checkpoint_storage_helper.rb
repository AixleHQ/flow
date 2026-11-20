# frozen_string_literal: true

require "rubygems/package"
require "zlib"

# A suspended session's archive goes from the container straight to object storage
# (Sessions::Checkpoint), so suspend is only offered where the storage signs an upload.
# The tests' memory storage does not; this swaps in one that does, and that also holds
# what "the container uploaded" — the bytes a test gives it — under the signed key.
#
# The swap is on SessionCheckpointUploader itself: a Shrine subclass keeps its own copy
# of the storage registry.
module CheckpointStorageHelper
  class Storage < Shrine::Storage::Memory
    attr_accessor :uploaded_bytes

    def presign(id, method: :put, **_options)
      upload(StringIO.new(uploaded_bytes.to_s), id)
      { url: "https://bucket.test/cache/#{id}", method: method }
    end
  end

  # The store hands out a URL the container can download from, as S3 signs one.
  class Store < Shrine::Storage::Memory
    def url(id, **) = "https://bucket.test/store/#{id}"
  end

  def use_checkpoint_storage(archive: "")
    @checkpoint_storages_original = SessionCheckpointUploader.storages.slice(:cache, :store)
    storage = Storage.new
    storage.uploaded_bytes = archive
    SessionCheckpointUploader.storages[:cache] = storage
    SessionCheckpointUploader.storages[:store] = Store.new
  end

  def restore_checkpoint_storage
    SessionCheckpointUploader.storages.merge!(@checkpoint_storages_original) if @checkpoint_storages_original
  end

  # A checkpoint archive shaped as the container builds it: a gzipped tar holding
  # workspace.tar, itself a tar of /workspace entries named "./<path>".
  def checkpoint_archive(workspace_files: {})
    workspace = tar_bytes(workspace_files.transform_keys { |path| "./#{path}" })
    gzip_tar("workspace.tar" => workspace, "repos/.keep" => "")
  end

  def create_checkpoint(session, manifest: {}, archive: checkpoint_archive)
    file = SessionCheckpointUploader.uploaded_file(
      id: "seed-#{SecureRandom.hex(4)}.tar.gz", storage: :store, metadata: { "size" => archive.bytesize }
    )
    SessionCheckpointUploader.storages[:store].upload(StringIO.new(archive), file.id)
    SessionCheckpoint.create!(terminal_session: session, archive_data: file.to_json, byte_size: archive.bytesize,
                              manifest: { "version" => 1, "workspace" => { "included" => true } }.merge(manifest))
  end

  private

  def tar_bytes(files)
    io = StringIO.new(+"")
    Gem::Package::TarWriter.new(io) do |tar|
      files.each { |name, content| tar.add_file_simple(name, 0o644, content.bytesize) { |f| f.write(content) } }
    end
    io.string
  end

  def gzip_tar(files)
    gz = StringIO.new(+"")
    writer = Zlib::GzipWriter.new(gz)
    writer.write(tar_bytes(files))
    writer.close
    gz.string
  end
end
