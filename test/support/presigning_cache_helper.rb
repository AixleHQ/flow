# frozen_string_literal: true

# Shrine's in-memory cache storage of the tests cannot sign an upload, as the
# filesystem storage of development cannot, and Runners::ResultUploads then
# issues no slots (a known limitation, DESIGN.md §6.4). A test of the uploads
# swaps in a storage that signs: the URL is a made-up one, and the fake host
# runner (ContainerRuntime::FakeHostRunner) writes to the storage itself.
module PresigningCacheHelper
  class Storage < Shrine::Storage::Memory
    def presign(id, method: :put, **_options)
      { url: "https://bucket.test/cache/#{id}", method: method }
    end
  end

  def use_presigning_cache
    original = Shrine.storages[:cache]
    Shrine.storages[:cache] = Storage.new
    @presigning_cache_original = original
  end

  def restore_cache_storage
    Shrine.storages[:cache] = @presigning_cache_original if @presigning_cache_original
  end
end
