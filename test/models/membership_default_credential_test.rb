# frozen_string_literal: true

require "test_helper"

# The default agent credential is a property of the MEMBERSHIP: the same person
# has a separate, separately-billed credential per company, so "my default
# agent" only means anything inside one company.
class MembershipDefaultCredentialTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @membership = @user.company_memberships.sole
  end

  test "default_agent_runtime returns the agent_type of the default credential" do
    create(:agent_credential, user: @user, company: @company, agent_type: "gemini_cli")

    assert_equal "gemini_cli", @membership.reload.default_agent_runtime
  end

  test "default_agent_runtime is nil when there is no default" do
    assert_nil @membership.default_agent_runtime
  end

  test "the first credential created in a company becomes that membership's default" do
    credential = create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")

    assert_equal credential.id, @membership.reload.default_agent_credential_id
  end

  test "a credential from ANOTHER company cannot be the default here" do
    other_company = create(:company)
    create(:company_membership, user: @user, company: other_company)
    foreign = create(:agent_credential, user: @user, company: other_company, agent_type: "claude_code")

    @membership.default_agent_credential_id = foreign.id

    assert_not @membership.valid?
    assert_includes @membership.errors[:default_agent_credential_id],
                    "must be a credential of this member in this company"
  end

  test "another member's credential cannot be the default" do
    other_user = create(:user, company: @company)
    other_cred = create(:agent_credential, user: other_user, company: @company, agent_type: "claude_code")

    @membership.default_agent_credential_id = other_cred.id

    assert_not @membership.valid?
  end

  test "nil default is valid" do
    @membership.default_agent_credential_id = nil
    assert @membership.valid?
  end

  test "destroying the default falls back to another credential in the same company" do
    first = create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    second = create(:agent_credential, user: @user, company: @company, agent_type: "gemini_cli")
    @membership.update!(default_agent_credential: first)

    first.destroy!

    assert_equal second.id, @membership.reload.default_agent_credential_id
  end

  test "each company keeps its own default" do
    other_company = create(:company)
    other_membership = create(:company_membership, user: @user, company: other_company)
    here = create(:agent_credential, user: @user, company: @company, agent_type: "claude_code")
    there = create(:agent_credential, user: @user, company: other_company, agent_type: "gemini_cli")

    assert_equal here.id, @membership.reload.default_agent_credential_id
    assert_equal there.id, other_membership.reload.default_agent_credential_id
  end
end
