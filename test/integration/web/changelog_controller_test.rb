# frozen_string_literal: true

require "test_helper"

class Web::ChangelogControllerTest < ActionDispatch::IntegrationTest
  CHANGELOG = <<~MD
    # Changelog

    ## [Unreleased]

    ## [1.0.0] - 2026-10-08

    The first tagged release.

    ### Added
    - **Workflows**: version history.

    [Unreleased]: https://github.com/AixleHQ/flow/compare/v1.0.0...develop
    [1.0.0]: https://github.com/AixleHQ/flow/releases/tag/v1.0.0
  MD

  setup { OpenSourceRepository.stubs(:changelog).returns(CHANGELOG) }

  test "a stranger reads the open-source repository's releases" do
    get changelog_path

    assert_response :success
    assert_inertia_page "Docs/ChangelogPage"
    assert_inertia_props do |props|
      assert_equal [ "1.0.0" ], props[:releases].map { |release| release[:version] }
      assert_equal "Workflows", props[:releases].first[:changes].first[:entries].first[:area]
      assert_equal OpenSourceRepository::CHANGELOG_URL, props[:sourceUrl]
    end
  end

  test "the star count arrives after the page, so GitHub never holds the page up" do
    OpenSourceRepository.expects(:stars).never

    get changelog_path

    assert_inertia_props { |props| assert_not props.key?(:githubStars) }
  end

  test "the star count is served on the follow-up request" do
    OpenSourceRepository.stubs(:stars).returns(2417)

    get changelog_path, headers: {
      "X-Inertia" => "true",
      "X-Inertia-Partial-Component" => "Docs/ChangelogPage",
      "X-Inertia-Partial-Data" => "githubStars"
    }

    assert_response :success
    assert_equal 2417, JSON.parse(response.body).dig("props", "githubStars")
  end

  test "a signed-in member reads it too" do
    company = create(:company)
    sign_in_as(create(:user, :admin, :onboarding_completed, company: company, password: AuthHelper::TEST_PASSWORD))

    get changelog_path

    assert_inertia_page "Docs/ChangelogPage"
  end
end
