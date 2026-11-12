# frozen_string_literal: true

require "test_helper"

# Runners::ResultUploads: the signed upload slots of an op whose output may be
# over the 1 MiB cap (runner/protocol/PROTOCOL.md §6.5).
class Runners::ResultUploadsTest < ActiveSupport::TestCase
  include PresigningCacheHelper

  setup do
    use_presigning_cache
    @slots = Runners::ResultUploads.issue(%w[stdout stderr], deadline_at: 2.minutes.from_now)
  end

  teardown do
    Runners::ResultUploads.discard(@slots)
    restore_cache_storage
  end

  def upload(slot, bytes)
    Shrine.storages[:cache].upload(StringIO.new(bytes), slot.id)
  end

  test "one slot per output, each its own object, with the platform's limit" do
    assert_equal %w[stdout stderr], @slots.keys
    assert_equal 2, @slots.values.map(&:id).uniq.size
    assert_equal [ Settings.runners.upload_limit ] * 2, @slots.values.map(&:max_bytes)
    assert_equal 33_554_432, Settings.runners.upload_limit
  end

  test "the payload carries each slot's id, URL and limit, and nothing of the storage" do
    payload = Runners::ResultUploads.payload(@slots)

    assert_equal %w[stdout stderr], payload.keys
    assert_equal %w[id max_bytes url], payload["stdout"].keys.sort
    assert_equal @slots["stdout"].id, payload["stdout"]["id"]
    assert_includes payload["stdout"]["url"], "cache/#{@slots['stdout'].id}"
  end

  test "where the storage cannot sign, uploads are not available, and a slot cannot be issued" do
    restore_cache_storage

    assert_not Runners::ResultUploads.available?
    assert_raises(ArgumentError) { Runners::ResultUploads.issue(%w[stdout], deadline_at: 2.minutes.from_now) }
  ensure
    use_presigning_cache
  end

  test "where it signs, uploads are available, and the budget fits 32 MiB at 1 MiB/s and the result" do
    assert Runners::ResultUploads.available?
    assert_equal 62, Runners::ResultUploads.budget
  end

  test "where the storage signs, the URL lives until the op's deadline and the grace, and at least a minute" do
    storage = mock("storage")
    storage.stubs(:respond_to?).with(:presign).returns(true)
    storage.stubs(:delete)
    storage.expects(:presign).with { |_id, **options| (options[:expires_in] - (120 + 300)).abs <= 2 }.returns(url: "https://b.test/u")
    storage.expects(:presign).with { |_id, **options| options[:expires_in] == 60 }.returns(url: "https://b.test/v")
    Shrine.stubs(:storages).returns(cache: storage)

    Runners::ResultUploads.issue(%w[stdout], deadline_at: 2.minutes.from_now)
    slots = Runners::ResultUploads.issue(%w[stdout], deadline_at: 1.hour.ago)

    assert_equal "https://b.test/v", slots["stdout"].url
  end

  test "claim returns the uploaded bytes of the slot the result names" do
    upload(@slots["stdout"], "a" * 10)

    bytes = Runners::ResultUploads.claim(@slots, { "stdout" => { "id" => @slots["stdout"].id, "size" => 10 } }, "stdout")

    assert_equal "a" * 10, bytes
  end

  test "claim is nil when the result names no upload for the output" do
    assert_nil Runners::ResultUploads.claim(@slots, nil, "stdout")
    assert_nil Runners::ResultUploads.claim(@slots, "x", "stdout")
    assert_nil Runners::ResultUploads.claim(@slots, { "stderr" => { "id" => "x", "size" => 1 } }, "stdout")
  end

  test "claim refuses what the runner's word does not back" do
    upload(@slots["stdout"], "a" * 10)
    stdout = @slots["stdout"].id
    refused = [
      [ "an output the op had no slot for", { "content" => { "id" => stdout, "size" => 10 } }, "content" ],
      [ "another id", { "stdout" => { "id" => @slots["stderr"].id, "size" => 10 } }, "stdout" ],
      [ "an id that is not a string", { "stdout" => { "id" => 1, "size" => 10 } }, "stdout" ],
      [ "an entry that is not an object", { "stdout" => stdout }, "stdout" ],
      [ "another size", { "stdout" => { "id" => stdout, "size" => 9 } }, "stdout" ],
      [ "no size", { "stdout" => { "id" => stdout } }, "stdout" ],
      [ "an object that was never uploaded", { "stderr" => { "id" => @slots["stderr"].id, "size" => 3 } }, "stderr" ]
    ]

    refused.each do |what, reported, name|
      assert_raises(Runners::ResultUploads::Unreadable, what) { Runners::ResultUploads.claim(@slots, reported, name) }
    end
  end

  test "claim refuses an object over the slot's limit without reading it whole" do
    upload(@slots["stdout"], "a" * 30)
    small = @slots["stdout"].with(max_bytes: 20)

    error = assert_raises(Runners::ResultUploads::Unreadable) do
      Runners::ResultUploads.claim({ "stdout" => small }, { "stdout" => { "id" => small.id, "size" => 30 } }, "stdout")
    end

    assert_match(/over 20 bytes/, error.message)
  end

  test "discard removes the objects, and a storage that fails leaves them to the prefix's lifecycle rule" do
    upload(@slots["stdout"], "x")
    Runners::ResultUploads.discard(@slots)
    assert_not @slots["stdout"].upload.uploaded?

    broken = @slots["stderr"].upload
    broken.stubs(:delete).raises(Errno::ECONNRESET)
    assert_nothing_raised { Runners::ResultUploads.discard({ "stderr" => @slots["stderr"] }) }
  end
end
