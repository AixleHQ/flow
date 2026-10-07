# frozen_string_literal: true

require "test_helper"

# The Aixle Flow YouTrack app's side of Connect, through the real public
# endpoints. The instance behind the token is FakeYoutrack::Api.
class Integrations::YoutrackPairingsTest < ActionDispatch::IntegrationTest
  APP = FakeYoutrack::Api::APP
  OPS = FakeYoutrack::Api::OPS

  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @youtrack = stub_youtrack!
    @company = create(:company, name: "Acme")
    @user = create(:user, :admin, company: @company, name: "Jane Doe")
    @project = create(:project, company: @company, owner: @user, name: "Support")
  end

  def bearer(secret) = { "Authorization" => "Bearer #{secret}" }

  def complete(pairing, secret, **body)
    post complete_youtrack_pairing_path(pairing.public_id), headers: bearer(secret), as: :json, params: {
      app_version: "1.0.0", instance_url: "https://acme.youtrack.cloud", token: "perm:minted",
      service_user: { id: "1-1", login: "aixle" }, projects: [ { id: APP, key: "APP", name: "Application" } ]
    }.merge(body)
  end

  test "a pairing Aixle started is read by the app, completed once, and hands back each project's events URL" do
    pairing, secret = YoutrackPairing.start!(instance_url: "https://acme.youtrack.cloud", project: @project, user: @user)

    get youtrack_pairing_path(pairing.public_id), headers: bearer(secret).merge("Origin" => "null")
    assert_response :success
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
    assert_equal [ "approved", "Acme", "Support", "Jane Doe" ],
                 response.parsed_body.then { |b| [ b["status"], b.dig("company", "name"), b.dig("project", "name"), b.dig("approved_by", "name") ] }

    complete(pairing, secret)

    assert_response :success
    integration = Integration.find_by!(project: @project, provider: "youtrack")
    subscription = integration.tracker_subscriptions.find_by!(external_scope_id: APP)
    project = response.parsed_body["projects"].sole
    assert_equal [ APP, subscription.secret, "State", "Assignee" ], project.values_at("id", "secret", "status_field", "assignee_field")
    assert_match %r{/webhooks/trackers/#{subscription.endpoint_token}\z}, project["events_url"]
    assert_match %r{/company/projects/#{@project.id}/trackers\z}, response.parsed_body["return_url"]
    assert_equal [ "perm:minted", @user ], [ integration.credentials_data["permanent_token"], integration.connected_by ]
    assert_equal [ "completed", integration ], [ pairing.reload.state, pairing.integration ]

    complete(pairing, secret)
    assert_response :conflict
  end

  test "the CORS preflight is answered for the app's null origin" do
    process :options, youtrack_pairings_path, headers: {
      "Origin" => "null", "Access-Control-Request-Method" => "POST", "Access-Control-Request-Headers" => "content-type"
    }

    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers["Access-Control-Allow-Methods"], "POST"
  end

  test "a pairing the app starts waits for its code, and cannot be completed before it is approved" do
    post youtrack_pairings_path, params: { instance_url: "https://Acme.youtrack.cloud/" }, as: :json

    assert_response :created
    body = response.parsed_body
    assert_match(/\A[A-Z2-9]{4}-[A-Z2-9]{4}\z/, body["code"])
    assert_equal youtrack_connect_url, body["approve_url"]
    pairing = YoutrackPairing.find_by!(public_id: body["id"])
    assert_equal [ "youtrack", "https://acme.youtrack.cloud" ], [ pairing.origin, pairing.instance_url ]

    complete(pairing, body["secret"])
    assert_response :conflict
    assert_equal 0, Integration.count

    post youtrack_pairings_path, params: { instance_url: "http://acme.youtrack.cloud" }, as: :json
    assert_response :unprocessable_content
  end

  test "a wrong secret and an unknown pairing look alike; an expired one is refused" do
    pairing, secret = YoutrackPairing.start!(instance_url: "https://acme.youtrack.cloud", project: @project, user: @user)

    get youtrack_pairing_path(pairing.public_id), headers: bearer("#{secret}x")
    assert_response :not_found
    get youtrack_pairing_path("nope"), headers: bearer(secret)
    assert_response :not_found

    travel YoutrackPairing::EXPIRY + 1.second do
      complete(pairing, secret)
      assert_response :conflict
      assert_equal "not_approved", response.parsed_body["error"]
    end
  end

  test "a token for another instance, another user, or an unseen project stores nothing" do
    pairing, secret = YoutrackPairing.start!(instance_url: "https://acme.youtrack.cloud", project: @project, user: @user)

    complete(pairing, secret, instance_url: "https://evil.youtrack.cloud")
    assert_equal [ 422, "instance_mismatch" ], [ response.status, response.parsed_body["error"] ]

    complete(pairing, secret, service_user: { login: "jdoe" })
    assert_response :unprocessable_content

    complete(pairing, secret, projects: [ { id: "0-9" } ])
    assert_response :unprocessable_content

    @youtrack.fail_next(:me, Trackers::Error.new("YouTrack rejected the permanent token", code: "not_authorized"))
    complete(pairing, secret)
    assert_equal [ 422, "not_authorized" ], [ response.status, response.parsed_body["error"] ]

    assert_equal [ 0, "approved" ], [ Integration.count, pairing.reload.state ]
  end

  test "an approver who lost write access to the project cannot have the pairing completed" do
    viewer = create(:user, :viewer, company: @company)
    create(:project_collaborator, project: @project, user: viewer)
    pairing, secret = YoutrackPairing.start!(instance_url: "https://acme.youtrack.cloud", project: @project, user: viewer)

    complete(pairing, secret)

    assert_response :forbidden
    assert_equal 0, Integration.count
  end
end
