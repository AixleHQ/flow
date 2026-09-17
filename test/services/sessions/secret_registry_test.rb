# frozen_string_literal: true

require "test_helper"

module Sessions
  class SecretRegistryTest < ActiveSupport::TestCase
    setup do
      @runtime = stub_container_runtime
      @company = create(:company)
      @user = create(:user, :admin, company: @company)
      @project = create(:project, company: @company, owner: @user)
      @session = create(:terminal_session, :agent_session, :running, user: @user, project: @project)
    end

    teardown { cleanup_runtime_overrides }

    def hand_out(name, value, item_type: :secret)
      item = create(:config_item, item_type, scope: @project, name: name, value: value)
      ConfigItemAccess.record!(config_item: item, session: @session, user: @user)
      item
    end

    def published
      raw = @runtime.read_file(@session.container_id, SecretRegistry::LIST_PATH)
      return [] if raw.blank?

      raw.split("\n").reject(&:blank?).map { |line| Base64.strict_decode64(line) }
    end

    test "publishes every secret the session has been handed" do
      hand_out("STRIPE_KEY", "sk_live_abc")
      hand_out("DB_PASSWORD", "hunter2")

      assert SecretRegistry.publish!(@session)
      assert_equal %w[sk_live_abc hunter2].sort, published.sort
    end

    test "leaves out a variable, which is not a secret to hide" do
      hand_out("STRIPE_KEY", "sk_live_abc")
      hand_out("API_BASE", "https://api.test", item_type: :variable)

      SecretRegistry.publish!(@session)

      assert_equal [ "sk_live_abc" ], published
    end

    test "rewrites the list whole, so a republish covers everything handed out so far" do
      hand_out("STRIPE_KEY", "sk_live_abc")
      SecretRegistry.publish!(@session)
      hand_out("DB_PASSWORD", "hunter2")

      SecretRegistry.publish!(@session)

      assert_equal 2, published.size
    end

    test "keeps one value on one line even when the secret contains newlines" do
      hand_out("PRIVATE_KEY", "-----BEGIN KEY-----\nline two\n-----END KEY-----")

      SecretRegistry.publish!(@session)

      raw = @runtime.read_file(@session.container_id, SecretRegistry::LIST_PATH)
      assert_equal 1, raw.split("\n").reject(&:blank?).size
      assert_includes published.first, "line two"
    end

    test "writes the list as root so the agent cannot quietly empty it" do
      hand_out("STRIPE_KEY", "sk_live_abc")

      SecretRegistry.publish!(@session)

      attributes = @runtime.file_attributes(SecretRegistry::LIST_PATH)
      assert_equal 0, attributes[:uid]
      assert_equal 0, attributes[:gid]
      assert_equal SecretRegistry::FILE_MODE, attributes[:mode]
    end

    test "reports success for a session with no container, where no log is being written" do
      session = create(:terminal_session, :agent_session, user: @user, project: @project)

      assert SecretRegistry.publish!(session)
    end

    test "reports failure when the container cannot take the list" do
      hand_out("STRIPE_KEY", "sk_live_abc")
      @runtime.stubs(:write_file).raises(ContainerRuntime::ContainerUnreachableError.new(container_identifier: "gone"))

      refute SecretRegistry.publish!(@session)
    end
  end
end
