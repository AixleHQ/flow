# frozen_string_literal: true

require "test_helper"

module ProjectTeams
  class PickerTest < ActiveSupport::TestCase
    # Stands in for a runtime adapter: the vendor call is contract-tested with each
    # adapter; here only the reading each credential reports matters.
    class UsageAdapter
      def initialize(utilization_by_token)
        @utilization_by_token = utilization_by_token
      end

      def fetch_subscription_usage(config)
        utilization = @utilization_by_token[config["api_key"]]
        return { status: "unavailable" } if utilization.nil?

        { status: "ok", windows: [ { key: "kiro_credits", utilization: utilization, resets_at: nil } ] }
      end
    end

    setup do
      @owner = create(:user, :with_company)
      @company = @owner.companies.first
      @project = create(:project, company: @company, owner: @owner)
      @workflow = create(:workflow, scope: @project)
      create(:step, workflow: @workflow)
      @team = create(:project_team, project: @project, name: "Planner")
      @anna, @pavel, @olga = %w[Anna Pavel Olga].map { |name| member(name) }
    end

    def member(name, runtime: "kiro_cli", token: name.downcase)
      user = create(:user, company: @company, name: name)
      @project.add_collaborator(user)
      create(:agent_credential, user: user, company: @company, agent_type: runtime, config_data: { "api_key" => token })
      create(:project_team_member, project_team: @team, user: user, position: @team.memberships.count)
      user
    end

    def pick(**options)
      Picker.call(team: @team.reload, workflow: @workflow, **options)
    end

    test "priority gives every run to the first member who can take it" do
      3.times { assert_equal @anna, pick.user }
      assert_nil @team.reload.last_picked_user_id
    end

    test "passes over a member whose credential is out of quota until the hold ends" do
      credential = AgentCredential.find_by!(user: @anna)
      credential.update_column(:quota_exhausted_until, 2.hours.from_now)

      result = pick
      assert_equal @pavel, result.user
      assert_match(/Kiro CLI quota exhausted until/, result.skipped.sole.reason)

      travel 3.hours do
        assert_equal @anna, pick.user
      end
    end

    test "a member needs a credential for every runtime the steps pin" do
      create(:step, workflow: @workflow, required_agent_runtime: "codex")
      create(:agent_credential, user: @olga, company: @company, agent_type: "codex")

      result = pick
      assert_equal @olga, result.user
      assert_equal [ "has no Codex connected" ] * 2, result.skipped.map(&:reason)
    end

    # Losing access normally takes a member out of the team (Management.prune!);
    # the picker still has to refuse anyone left behind by a write that skipped it.
    test "skips viewers, people who left the project and people without an agent" do
      CompanyMembership.find_by!(user: @anna, company: @company).update_column(:role, "viewer")
      ProjectCollaborator.where(project: @project, user: @pavel).delete_all
      AgentCredential.where(user: @olga).delete_all

      result = pick
      assert_not result.picked?
      assert_equal "No member of team \"Planner\" can take this run — Anna: is a viewer, and viewers can't start runs; " \
                   "Pavel: no longer has access to the project; Olga: has no agent connected in this company.",
                   result.message
    end

    test "round robin hands runs out in turn and remembers whose turn it is" do
      @team.update!(strategy: "round_robin")

      assert_equal [ @anna, @pavel, @olga, @anna ], Array.new(4) { pick.user }
      assert_equal @anna.id, @team.reload.last_picked_user_id
    end

    test "round robin skips a member who cannot take the run without losing their place" do
      @team.update!(strategy: "round_robin")
      AgentCredential.find_by!(user: @pavel).update_column(:quota_exhausted_until, 1.hour.from_now)

      assert_equal [ @anna, @olga, @anna ], Array.new(3) { pick.user }
    end

    test "a preview says who is next and why the others are passed over, without moving the cursor" do
      @team.update!(strategy: "round_robin")
      AgentCredential.find_by!(user: @anna).update_column(:quota_exhausted_until, 2.hours.from_now)

      preview = Picker.preview(@team.reload)

      assert_equal @pavel, preview.next_user
      assert_equal [ @anna ], preview.skipped.map(&:user)
      assert_in_delta 2.hours.from_now, preview.skipped.sole.held_until, 1.second
      assert_nil @team.reload.last_picked_user_id
    end

    test "a member already running a session on the run's runtime is passed over while another is free" do
      create(:terminal_session, :running, user: @anna, project: @project, agent_type: "kiro_cli")

      assert_equal @pavel, pick.user

      create(:terminal_session, :running, user: @pavel, project: @project, agent_type: "kiro_cli")
      create(:terminal_session, :running, user: @olga, project: @project, agent_type: "kiro_cli")
      assert_equal @anna, pick.user, "with everyone busy, the strategy's own pick still takes it"
    end

    test "a quota retry passes over the member it is moving away from" do
      assert_equal @pavel, pick(exclude_user_ids: [ @anna.id ]).user
    end

    test "most remaining picks the member with the most quota left, and falls back to turns without readings" do
      Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
      @team.update!(strategy: "most_remaining")
      adapter = UsageAdapter.new("anna" => 90.0, "pavel" => 20.0, "olga" => 55.0)
      usage = Agents::SubscriptionUsageService.new(adapter_resolver: ->(_type) { adapter })
      [ @anna, @pavel, @olga ].each { |user| usage.usage_for(AgentCredential.find_by!(user: user)) }

      assert_equal @pavel, pick(usage: usage).user

      blind = Agents::SubscriptionUsageService.new(adapter_resolver: ->(_type) { UsageAdapter.new({}) })
      Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
      assert_equal @olga, pick(usage: blind).user
    end
  end
end
