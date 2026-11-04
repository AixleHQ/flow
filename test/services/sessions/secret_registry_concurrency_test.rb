# frozen_string_literal: true

require "test_helper"

module Sessions
  # Agents call get_config_item in parallel, and each call rewrites the whole list
  # through an exec that takes seconds. In production a publish that started first
  # finished last with fewer secrets, and the one it dropped reached the proxy log and
  # the transcript unmasked. Separate connections, because that is where the race is.
  class SecretRegistryConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    test "a publish still writing cannot be overtaken by one that saw more secrets" do
      runtime = stub_container_runtime
      user = create(:user, :with_company)
      company = user.companies.first
      project = create(:project, owner: user, company: company)
      session = create(:terminal_session, :agent_session, :running, user: user, project: project)
      first = create(:config_item, :secret, scope: project, name: "FIRST_KEY", value: "first-secret-value")
      second = create(:config_item, :secret, scope: project, name: "SECOND_KEY", value: "second-secret-value")
      ConfigItemAccess.record!(config_item: first, session: session, user: user)

      overtaker = nil
      runtime.on_next_write(SecretRegistry::LIST_PATH) do
        overtaker = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ConfigItemAccess.record!(config_item: second, session: session, user: user)
            SecretRegistry.publish!(session, runtime: runtime)
          end
        end
        # Long enough for an unserialized second publish to finish ahead of this one.
        overtaker.join(1)
      end

      assert SecretRegistry.publish!(session, runtime: runtime)
      assert overtaker.value

      list = runtime.read_file(session.container_id, SecretRegistry::LIST_PATH).split.map { |line| Base64.strict_decode64(line) }
      assert_equal %w[first-secret-value second-secret-value], list.sort
    ensure
      overtaker&.join
      cleanup_runtime_overrides
      ConfigItemAccess.where(terminal_session_id: session.id).delete_all if session
      TerminalSession.where(id: session.id).delete_all if session
      ConfigItem.where(scope: project).delete_all if project
      project&.delete
      user&.company_memberships&.delete_all
      UserIdentity.where(user_id: user.id).delete_all if user
      UserSession.where(user_id: user.id).delete_all if user
      user&.delete
      CompanyAuthPolicy.where(company_id: company.id).delete_all if company
      IdentityProvider.where(company_id: company.id).delete_all if company
      company&.delete
    end
  end
end
