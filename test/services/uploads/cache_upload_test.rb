# frozen_string_literal: true

require "test_helper"

# Uploads::CacheUpload: a slot in Shrine's :cache storage that a client PUTs
# into, and what the platform does with the bytes afterwards.
class Uploads::CacheUploadTest < ActiveSupport::TestCase
  setup { @upload = Uploads::CacheUpload.mint(filename: "report.PDF") }

  teardown { @upload.delete }

  test "a minted slot has a random key under cache/, and only a short alphanumeric extension of the filename" do
    assert_match(%r{\Acache/\h{60}\.pdf\z}, @upload.key)
    assert_match(%r{\Acache/\h{60}\z}, Uploads::CacheUpload.mint(filename: "x.<script>").key)
  end

  test "read returns the object's bytes as a binary string, and absent is Missing" do
    assert_raises(Uploads::CacheUpload::Missing) { @upload.read(limit: 10) }

    Shrine.storages[:cache].upload(StringIO.new("héllo\xFF".b), @upload.id)
    data = @upload.read(limit: 10)

    assert_equal "héllo\xFF".b, data
    assert_equal Encoding::BINARY, data.encoding
  end

  test "an object over the limit is TooLarge, and one at the limit is read" do
    Shrine.storages[:cache].upload(StringIO.new("x" * 11), @upload.id)

    assert_raises(Uploads::CacheUpload::TooLarge) { @upload.read(limit: 10) }
    assert_equal 11, @upload.read(limit: 11).bytesize
  end

  test "an empty object is read as an empty string" do
    Shrine.storages[:cache].upload(StringIO.new(""), @upload.id)

    assert_equal "", @upload.read(limit: 10)
  end

  test "delete removes the object, and an absent one is not an error" do
    Shrine.storages[:cache].upload(StringIO.new("x"), @upload.id)

    @upload.delete
    @upload.delete

    assert_not @upload.uploaded?
  end

  test "a storage that signs its own uploads is asked for a URL of the given lifetime" do
    storage = mock("storage")
    storage.expects(:presign).with(@upload.id, method: :put, expires_in: 90).returns(url: "https://bucket.test/cache/x?sig=1")
    storage.stubs(:respond_to?).with(:presign).returns(true)
    Shrine.stubs(:storages).returns(cache: storage)

    assert_equal "https://bucket.test/cache/x?sig=1", @upload.presigned_put_url(expires_in: 90)
  end

  test "the storage of the tests cannot sign, so there is no presigned URL" do
    assert_nil @upload.presigned_put_url(expires_in: 90)
  end
end
