# frozen_string_literal: true

require "test_helper"

class TeamMailerTest < ActionMailer::TestCase
  setup do
    @owner = create(:user, :with_company, name: "Olga")
    @project = create(:project, company: @owner.companies.first, owner: @owner, name: "Ops")
    @team = create(:project_team, project: @project, name: "Planner")
    @member = create(:user, email: "anna@example.com", name: "Anna")
  end

  test "being added says whose subscription runs spend and how to leave" do
    email = TeamMailer.added(@member, @team, @owner)

    assert_equal [ "anna@example.com" ], email.to
    assert_equal "You were added to team Planner in Ops", email.subject
    body = email.text_part.decoded
    assert_match(/Olga added you to team Planner in project Ops/, body)
    assert_match(/your own agent subscription/, body)
    assert_match(%r{/profile}, body)
  end

  test "being taken out, and a member opting out, are both said" do
    assert_match(/took you out of team Planner/, TeamMailer.removed(@member, @team, @owner).text_part.decoded)
    assert_match(/no longer in team Planner in project Ops: you are now a viewer/,
                 TeamMailer.removed(@member, @team, nil, reason: "now a viewer").text_part.decoded)

    email = TeamMailer.member_opted_out(@owner, @member, [ @team ])
    assert_equal [ @owner.email ], email.to
    assert_match(%r{Anna turned on "Don't let anyone add me to a team".*Planner}m, email.text_part.decoded)
    assert_match(%r{/company/projects/#{@project.id}/teams}, email.text_part.decoded)
  end
end
