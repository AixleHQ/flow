# frozen_string_literal: true

require "test_helper"

# The rules every tracker file transfer follows (docs/design/tracker-attachments.md §9.1).
class Trackers::FileTransferTest < ActiveSupport::TestCase
  setup do
    resolve_hosts_publicly!
    @transfer = Trackers::FileTransfer.new(name: "Tracker", hosts: [ "api.tracker.test" ], redirect_hosts: [ /\A[a-z]+\.media\.test\z/ ])
  end

  def download(url, headers: { "Authorization" => "Bearer secret" }, max_bytes: 1.megabyte, **options)
    io = StringIO.new
    @transfer.download(url, io: io, max_bytes: max_bytes, headers: headers, **options)
    io.string
  end

  test "a host off the list is never asked, with or without a credential" do
    error = assert_raises(Trackers::Error) { download("https://evil.test/file") }

    assert_equal "not_found", error.code
    assert_not_requested :get, "https://evil.test/file"
  end

  test "only https is fetched" do
    assert_equal "validation_failed", assert_raises(Trackers::Error) { download("http://api.tracker.test/file") }.code
  end

  test "a redirect to a media host is followed without the credential" do
    stub_request(:get, "https://api.tracker.test/file").to_return(status: 303, headers: { "Location" => "https://eu.media.test/f?sig=1" })
    media = stub_request(:get, "https://eu.media.test/f?sig=1").with { |r| r.headers["Authorization"].nil? }.to_return(status: 200, body: "bytes")

    assert_equal "bytes", download("https://api.tracker.test/file")
    assert_requested media
  end

  test "a redirect anywhere else is refused" do
    stub_request(:get, "https://api.tracker.test/file").to_return(status: 302, headers: { "Location" => "https://evil.test/steal" })

    assert_equal "not_found", assert_raises(Trackers::Error) { download("https://api.tracker.test/file") }.code
    assert_not_requested :get, "https://evil.test/steal"
  end

  test "a body past the cap is refused while it streams" do
    stub_request(:get, "https://api.tracker.test/file").to_return(status: 200, body: "x" * 20)

    error = assert_raises(Trackers::Error) { download("https://api.tracker.test/file", max_bytes: 10) }

    assert_equal [ "too_large", 10 ], [ error.code, error.details[:max_bytes] ]
  end

  test "a refused credential is renewed once" do
    stub_request(:get, "https://api.tracker.test/file").with(headers: { "Authorization" => "Bearer old" }).to_return(status: 401)
    stub_request(:get, "https://api.tracker.test/file").with(headers: { "Authorization" => "Bearer new" }).to_return(status: 200, body: "ok")

    assert_equal "ok", download("https://api.tracker.test/file", headers: { "Authorization" => "Bearer old" },
                                                                 reauthorize: -> { { "Authorization" => "Bearer new" } })
  end

  test "an upload refused as too large says so, and one the server failed is of unknown outcome" do
    stub_request(:post, "https://api.tracker.test/up").to_return({ status: 413 }, { status: 502 })
    send = -> { @transfer.send_request(:post, "https://api.tracker.test/up", body: StringIO.new("a"), content_type: "text/plain", size: 1) }

    assert_equal "too_large", assert_raises(Trackers::Error) { send.call }.code
    assert_raises(Trackers::Error::OutcomeUnknown) { send.call }
  end
end
