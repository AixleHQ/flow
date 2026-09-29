# frozen_string_literal: true

require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "the app is served its policy report-only, with the structural directives enforced" do
    get login_path

    enforced = response.headers["Content-Security-Policy"]
    reported = response.headers["Content-Security-Policy-Report-Only"]
    assert_equal "base-uri 'self'; object-src 'none'; frame-ancestors 'self'", enforced
    assert_includes reported, "base-uri 'self'"
    assert_includes reported, "frame-ancestors 'self'"
    assert_not_includes reported[/script-src ([^;]*)/, 1].to_s.split, "https:", "any https URL must not be a script source"
    assert_includes reported, "media-src 'self'"
  end

  test "the app layout's inline script carries the nonce the policy names" do
    get login_path

    nonce = response.headers["Content-Security-Policy-Report-Only"][/'nonce-([^']+)'/, 1]
    assert nonce, "script-src names no nonce"
    assert_includes response.body, %(nonce="#{nonce}")
  end

  test "the landing page keeps inline script, and names no nonce that would switch it off" do
    get root_path

    reported = response.headers["Content-Security-Policy-Report-Only"]
    assert_match(/script-src[^;]*'unsafe-inline'/, reported)
    assert_no_match(/'nonce-/, reported)
  end

  test "a share link's own policy is left alone" do
    user = create(:user, :with_company)
    project = create(:project, company: user.companies.first, owner: user)
    asset = create(:asset, scope: project, created_by: user)
    token = asset.share!

    get public_asset_path(token: token)

    assert_equal "frame-ancestors *", response.headers["Content-Security-Policy"]
  end

  test "a violation report is logged with only its triage fields" do
    report = { "csp-report" => { "document-uri" => "https://app.example/x", "violated-directive" => "script-src",
                                 "blocked-uri" => "https://evil.example/a.js", "original-policy" => "x" * 5000,
                                 "script-sample" => "alert(1)\n[forged] line" } }

    logged = capture_log { post "/csp-violation-report-endpoint", params: report.to_json, headers: { "Content-Type" => "application/csp-report" } }

    assert_response :no_content
    assert_includes logged, %("violated-directive":"script-src")
    assert_not_includes logged, "original-policy"
    assert_not_includes logged, "forged"
  end

  test "an oversized report is dropped unread" do
    logged = capture_log do
      post "/csp-violation-report-endpoint", params: { "csp-report" => { "blocked-uri" => "x" * 20_000 } }.to_json,
                                             headers: { "Content-Type" => "application/csp-report" }
    end

    assert_response :no_content
    assert_not_includes logged, "CSP Violation"
  end

  private

  def capture_log
    io = StringIO.new
    previous = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = previous
  end
end
