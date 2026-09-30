# frozen_string_literal: true

require "test_helper"

class ContainerAssetUrlTest < ActiveSupport::TestCase
  OURS = "https://aixle.example.com/store/out.txt"
  SIGNED = "https://bucket.s3.amazonaws.com/store/out.txt" \
           "?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Signature=abc123&X-Amz-Expires=3600"

  # What the rewriting is for: the application serves its own files on the
  # Docker runtime, and the address it writes is the one a browser uses.
  test "an address of ours is moved to one the container can reach" do
    assert_equal "http://web:4000/store/out.txt", ContainerAssetUrl.call(OURS, host: "web:4000")
  end

  test "a scheme in the host is honoured" do
    assert_equal "https://assets.example.com/store/out.txt",
                 ContainerAssetUrl.call(OURS, host: "https://assets.example.com")
  end

  # The signature covers the host. Moving it produces a link that looks right
  # and answers 403, which reads as a broken tool rather than a broken URL.
  test "a presigned URL is left exactly as it was signed" do
    assert_equal SIGNED, ContainerAssetUrl.call(SIGNED, host: "https://bucket.s3.us-east-1.amazonaws.com")
  end

  test "nothing is rewritten without a host" do
    assert_equal OURS, ContainerAssetUrl.call(OURS, host: nil)
    assert_equal OURS, ContainerAssetUrl.call(OURS, host: "")
  end

  test "a blank url survives" do
    assert_nil ContainerAssetUrl.call(nil, host: "web:4000")
  end

  test "an unparseable url is returned rather than raised" do
    assert_equal "not a url", ContainerAssetUrl.call("not a url", host: "web:4000")
  end
end
