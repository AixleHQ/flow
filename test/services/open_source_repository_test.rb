# frozen_string_literal: true

require "test_helper"

class OpenSourceRepositoryTest < ActiveSupport::TestCase
  setup { Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new) }

  test "reads the star count from the repository" do
    stub_request(:get, OpenSourceRepository::API_URL)
      .to_return(status: 200, body: { full_name: "AixleHQ/flow", stargazers_count: 2417 }.to_json,
                 headers: { "Content-Type" => "application/json" })

    assert_equal 2417, OpenSourceRepository.stars
  end

  test "has no star count when GitHub refuses or cannot be reached" do
    stub_request(:get, OpenSourceRepository::API_URL)
      .to_return(status: 403, body: { message: "API rate limit exceeded" }.to_json)
    assert_nil OpenSourceRepository.stars

    Rails.cache.clear
    stub_request(:get, OpenSourceRepository::API_URL).to_timeout
    assert_nil OpenSourceRepository.stars

    Rails.cache.clear
    stub_request(:get, OpenSourceRepository::API_URL).to_return(status: 200, body: "<html>")
    assert_nil OpenSourceRepository.stars
  end

  test "reads CHANGELOG.md from the repository's default branch" do
    stub_request(:get, OpenSourceRepository::RAW_CHANGELOG_URL)
      .to_return(status: 200, body: "# Changelog\n\n## [1.1.0] - 2026-11-01 — “quoted”\n")

    changelog = OpenSourceRepository.changelog

    assert_includes changelog, "## [1.1.0]"
    assert_equal Encoding::UTF_8, changelog.encoding
    assert changelog.valid_encoding?
  end

  test "falls back to the changelog this build shipped with" do
    stub_request(:get, OpenSourceRepository::RAW_CHANGELOG_URL).to_return(status: 404)

    assert_equal Rails.root.join("CHANGELOG.md").read, OpenSourceRepository.changelog
  end

  test "asks GitHub again an hour after an answer" do
    stars = stub_request(:get, OpenSourceRepository::API_URL).to_return(status: 200, body: { stargazers_count: 7 }.to_json)

    2.times { OpenSourceRepository.stars }
    assert_requested stars, times: 1

    travel 61.minutes do
      OpenSourceRepository.stars
      assert_requested stars, times: 2
    end
  end

  test "asks GitHub again ten minutes after a failure, not on every page view" do
    stars = stub_request(:get, OpenSourceRepository::API_URL).to_return(status: 500)

    2.times { assert_nil OpenSourceRepository.stars }
    assert_requested stars, times: 1

    travel 11.minutes do
      OpenSourceRepository.stars
      assert_requested stars, times: 2
    end
  end
end
