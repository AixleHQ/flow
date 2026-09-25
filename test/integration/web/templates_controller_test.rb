# frozen_string_literal: true

require "test_helper"

class Web::TemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @template = create_catalog_template
  end

  test "a guest can browse the catalog" do
    get templates_path

    assert_response :success
    assert_inertia_page "Templates/IndexPage"
    assert_inertia_props do |props|
      props[:templates].pluck(:identifier) == [ "acme/dev-team-sdlc" ] && props[:signedIn] == false && props[:currentUser].nil?
    end
  end

  test "a revoked template is not listed" do
    @template.update!(revoked_at: Time.current, revocation_reason: "Broken.")

    get templates_path

    assert_inertia_props { |props| props[:templates].empty? }
  end

  test "a guest can read a template and is pointed at the install page for its version" do
    get template_path("acme", "dev-team-sdlc")

    assert_response :success
    assert_inertia_page "Templates/ShowPage"
    assert_inertia_props do |props|
      props[:installPath] == new_company_template_install_path(namespace: "acme", slug: "dev-team-sdlc", version: 3) &&
        props[:template][:boardColumns] == [ "Backlog", "Tech Design", "Code Review", "Done" ]
    end
  end

  test "an unknown template is a 404" do
    get template_path("acme", "no-such-template")

    assert_response :not_found
  end
end
