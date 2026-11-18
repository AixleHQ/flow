# frozen_string_literal: true

require "test_helper"

# The app's 404 page, reached the way production reaches it: through the
# exceptions app, with detailed exceptions off (ErrorsController,
# config/application.rb).
class NotFoundPageTest < ActionDispatch::IntegrationTest
  def as_in_production
    config = Rails.application.env_config
    saved = config.slice("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
    config.merge!("action_dispatch.show_exceptions" => :all, "action_dispatch.show_detailed_exceptions" => false)
    yield
  ensure
    config.merge!(saved)
  end

  test "a page that does not exist shows the not-found page, with the address that was asked for" do
    as_in_production { get "/no/such/page" }

    assert_response :not_found
    assert_select "h1", "Page not found"
    assert_select ".lines", /open \/no\/such\/page/
    assert_select "nav[aria-label='Where to go'] a", 3
  end

  test "a client that did not ask for a page keeps Rails' own answer" do
    as_in_production { get "/no/such/page", headers: { "Accept" => "application/json" } }

    assert_response :not_found
    assert_equal({ "status" => 404, "error" => "Not Found" }, response.parsed_body)
  end

  test "every way out of it leads to a page that exists" do
    as_in_production { get "/no/such/page" }

    hrefs = css_select("a").pluck("href").uniq
    assert_equal %w[/ /company/projects /docs], hrefs.sort
    hrefs.each { |href| assert Rails.application.routes.recognize_path(href), href }
  end
end
