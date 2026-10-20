# frozen_string_literal: true

require "test_helper"

class ProjectMove::PreflightTest < ActiveSupport::TestCase
  setup do
    @s = ProjectMoveScenario.new.build
  end

  test "reports what the move will do without doing any of it" do
    preflight = ProjectMove::Preflight.new(project: @s.project, target: @s.target)

    assert preflight.movable?, preflight.blockers.to_sentence
    assert_equal [ @s.outsider ], preflight.missing_members
    assert_equal [ @s.company_asset ], preflight.company_assets
    assert_equal [ @s.company_repository ], preflight.detached_repositories
    assert_equal [ @s.pending_run ], preflight.runs_to_cancel
    assert_equal [ @s.chat_binding ], preflight.chat_bindings
    assert_equal [ "Launchpad (2)", "launchpad-2" ], [ preflight.name_after, preflight.slug_after ]
    assert preflight.reservation_dropped?
    assert_equal [ @s.owner, @s.shared_member, @s.target_admin ].sort_by(&:name), preflight.owner_candidates.to_a

    assert_equal @s.source, @s.project.reload.company
    assert_equal "pending", @s.pending_run.reload.state
  end

  test "a live agent, the project's own company and an inactive company each block the move" do
    create(:terminal_session, :agent_session, project: @s.project, user: @s.owner, state: "running")
    @s.target.suspend!

    blockers = ProjectMove::Preflight.new(project: @s.project, target: @s.target).blockers
    own = ProjectMove::Preflight.new(project: @s.project, target: @s.source).blockers

    assert_equal [ "Contoso is suspended and cannot take projects.",
                   "1 session(s) are running in this project. Stop them before moving it." ], blockers
    assert_includes own, "The project already belongs to Northwind."
  end

  test "a queued session no run accounts for is cancelled on its own" do
    queued = create(:terminal_session, :agent_session, project: @s.project, user: @s.owner, state: "queued")

    preflight = ProjectMove::Preflight.new(project: @s.project, target: @s.target)

    assert_equal [ queued ], preflight.sessions_to_cancel
    assert preflight.movable?
  end

  test "names the people who have no agent credential in the target" do
    create(:agent_credential, user: @s.shared_member, company: @s.target)

    preflight = ProjectMove::Preflight.new(project: @s.project, target: @s.target)

    assert_not_includes preflight.people_without_agent_credentials, @s.shared_member
    assert_includes preflight.people_without_agent_credentials, @s.owner
  end
end
