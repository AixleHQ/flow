# frozen_string_literal: true

require "test_helper"

class ToolResultResourceTest < ActiveSupport::TestCase
  setup do
    @result = create(:tool_result)
  end

  def rendered(url_host:)
    JSON.parse(ToolResultResource.new(@result, params: { url_host: url_host }).to_json)
  end

  test "an address of ours is moved to one the container can reach" do
    @result.stubs(:stdout).returns(stub(url: "https://aixle.example.com/store/out.txt", metadata: {}))

    url = rendered(url_host: "web:4000")["stdout_url"]

    assert_equal "http://web:4000/store/out.txt", url
  end

  # The signature covers the host. Moving it produces a link that looks right
  # and answers 403.
  test "a presigned URL is left exactly as AWS signed it" do
    signed = "https://bucket.s3.amazonaws.com/store/out.txt" \
             "?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Signature=abc123&X-Amz-Expires=3600"
    @result.stubs(:stdout).returns(stub(url: signed, metadata: {}))

    url = rendered(url_host: "https://bucket.s3.us-east-1.amazonaws.com")["stdout_url"]

    assert_equal signed, url
  end

  test "nothing is rewritten when no host is configured" do
    @result.stubs(:stdout).returns(stub(url: "https://aixle.example.com/store/out.txt", metadata: {}))

    assert_equal "https://aixle.example.com/store/out.txt", rendered(url_host: nil)["stdout_url"]
  end
end
