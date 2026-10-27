# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # Racing workers need their own committed connections, so this test opts out
  # of the transactional wrapper and cleans up after itself.
  class SubscriptionServiceConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    THREADS = 4
    EVENT_TYPE = "workitem.created"
    WAIT = 5

    setup do
      with_azure_devops_enabled
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
      azure_project_id = SecureRandom.uuid
      @installation = create(:azure_devops_installation, :active, company: @company, approved_by: @user,
                                                                  approved_at: Time.current,
                                                                  allowed_project_ids: [ azure_project_id ])
      @integration = create(:integration, :azure_devops, :active, company: @company, project: @project,
                                                                  connected_by: @user,
                                                                  azure_devops_installation: @installation,
                                                                  azure_project_id: azure_project_id)
      stub_azure_token(tenant_id: @installation.tenant_id)
    end

    teardown do
      AzureDevopsSubscription.where(integration_id: @integration.id).delete_all
      @integration.delete
      @installation.delete
      # Before the user: projects.owner_id references it. Rows are deleted directly,
      # so `dependent: :destroy` never fires and every dependent is cleared by hand.
      @project.delete
      @user.company_memberships.delete_all
      UserIdentity.where(user_id: @user.id).delete_all
      UserSession.where(user_id: @user.id).delete_all
      @user.delete
      CompanyAuthPolicy.where(company_id: @company.id).delete_all
      IdentityProvider.where(company_id: @company.id).delete_all
      @company.delete
    end

    # The first POST is held open until every other worker is queued on the row
    # lock; a barrier waiting for all of them to POST would never open once fixed.
    test "concurrent setup of one connection creates one row and one Azure hook" do
      entered = Queue.new
      release = Queue.new
      posts = 0
      counter = Mutex.new
      stub_request(:post, %r{/_apis/hooks/subscriptions}).to_return do
        first = counter.synchronize { (posts += 1) == 1 }
        if first
          entered << true
          release.pop
        end
        { status: 200, headers: { "Content-Type" => "application/json" },
          body: { id: SecureRandom.uuid, status: "enabled" }.to_json }
      end

      threads = [ Thread.new { ensure_in_own_connection } ]
      assert entered.pop(timeout: WAIT), "the first worker never reached Azure"
      threads += Array.new(THREADS - 1) { Thread.new { ensure_in_own_connection } }
      wait_for_lock_waiters(THREADS - 1)
      release << true
      results = threads.map(&:value)

      rows = AzureDevopsSubscription.where(integration_id: @integration.id, event_type: EVENT_TYPE)
      assert_equal 1, rows.count
      assert_equal Array.new(THREADS) { [ rows.first.id ] }, results.map { |result| result.map(&:id) }
      assert rows.first.active?
      assert_requested :post, %r{/_apis/hooks/subscriptions}, times: 1
    ensure
      release&.push(true)
      threads&.each(&:join)
    end

    # The Sentry failure: workers released together against an empty table race
    # the INSERT on the unique index. Serialized scheduling still satisfies it.
    test "workers inserting the same row at once neither raise nor duplicate it" do
      stub_request(:post, %r{/_apis/hooks/subscriptions}).to_return do
        { status: 200, headers: { "Content-Type" => "application/json" },
          body: { id: SecureRandom.uuid, status: "enabled" }.to_json }
      end
      gate = Queue.new
      threads = Array.new(THREADS) do
        Thread.new do
          gate.pop
          ensure_in_own_connection
        end
      end
      THREADS.times { gate << true }
      results = threads.map(&:value)

      rows = AzureDevopsSubscription.where(integration_id: @integration.id, event_type: EVENT_TYPE)
      assert_equal 1, rows.count
      assert_equal Array.new(THREADS) { [ rows.first.id ] }, results.map { |result| result.map(&:id) }
      assert rows.first.active?
      assert_requested :post, %r{/_apis/hooks/subscriptions}, times: 1
    ensure
      threads&.each(&:join)
    end

    private

    # An integration record of its own per thread, as each job has: records are not thread-safe.
    def ensure_in_own_connection
      ActiveRecord::Base.connection_pool.with_connection do
        integration = Integration.find(@integration.id)
        SubscriptionService.new(integration).ensure_all!(event_types: [ EVENT_TYPE ], base_url: "https://aixle.test")
      end
    end

    # Bounded: without the row lock nobody waits, and the assertions say why.
    def wait_for_lock_waiters(count)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT
      loop do
        waiting = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
          SELECT count(*) FROM pg_stat_activity
          WHERE datname = current_database() AND wait_event_type = 'Lock'
        SQL
        break if waiting.to_i >= count || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.01
      end
    end
  end
end
