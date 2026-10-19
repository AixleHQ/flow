# frozen_string_literal: true

require "test_helper"

class Admin::CompanyInvitationsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @company = create(:company, name: "Northwind")
    @admin = create(:user, :super_admin, name: "Olga Operator", password: AuthHelper::TEST_PASSWORD)
  end

  test "only a super admin reaches the invitations" do
    company_admin = create(:user, :admin, company: @company, password: AuthHelper::TEST_PASSWORD)
    sign_in_as(company_admin)

    get new_admin_company_invitation_path(@company)
    assert_redirected_to admin_login_path

    assert_no_difference -> { CompanyMembership.count } do
      post admin_company_invitations_path(@company), params: { emails: "ann@example.com", role: "employee" }
    end
  end

  test "the company page leads to the invitations, which list its members" do
    member = create(:user, :employee, company: @company)
    sign_in_as(@admin)

    get admin_company_path(@company)
    assert_includes response.body, new_admin_company_invitation_path(@company)

    get new_admin_company_invitation_path(@company)
    assert_response :success
    assert_includes response.body, member.email
  end

  test "a pasted list is invited, and what was not sent is said" do
    member = create(:user, :employee, company: @company)
    sign_in_as(@admin)

    assert_enqueued_emails 2 do
      post admin_company_invitations_path(@company),
           params: { emails: "ann@example.com\nbob@example.com, #{member.email}", role: "viewer" }
    end

    assert_redirected_to new_admin_company_invitation_path(@company)
    assert_equal "Invitations sent to 2 addresses.", flash[:notice]
    assert_equal "Not invited: #{member.email} is already a member of this company.", flash[:alert]
    ann = @company.company_memberships.joins(:user).find_by!(users: { email: "ann@example.com" })
    assert { ann.invited? && ann.viewer? }

    follow_redirect!
    assert_includes response.body, "bob@example.com"
  end

  test "the invitation is from an administrator, never from the operator who sent it" do
    sign_in_as(@admin)

    perform_enqueued_jobs do
      post admin_company_invitations_path(@company), params: { emails: "ann@example.com", role: "employee" }
    end

    membership = @company.company_memberships.joins(:user).find_by!(users: { email: "ann@example.com" })
    assert_nil membership.invited_by
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "ann@example.com" ], mail.to
    [ mail.text_part, mail.html_part ].each do |part|
      body = part.body.to_s
      assert_includes body, "An administrator"
      refute_includes body, @admin.email
      refute_includes body, @admin.name
    end
  end

  test "an empty list asks for an address" do
    sign_in_as(@admin)

    post admin_company_invitations_path(@company), params: { emails: " \n ", role: "employee" }

    assert_redirected_to new_admin_company_invitation_path(@company)
    assert_equal "Enter at least one email address.", flash[:alert]
  end

  test "a new company invites its admin and its team, then shows who was invited" do
    sign_in_as(@admin)

    assert_enqueued_emails 3 do
      post admin_companies_path, params: {
        company: attributes_for(:company, name: "Contoso").merge(
          initial_admin_email: "boss@contoso.test",
          invite_emails: "ann@contoso.test\nbob@contoso.test",
          invite_role: "employee"
        )
      }
    end

    company = Company.find_by!(name: "Contoso")
    assert_redirected_to new_admin_company_invitation_path(company)
    assert_match(/Invitations sent to 3 addresses\.\z/, flash[:notice])
    memberships = company.company_memberships.includes(:user).index_by { |m| m.user.email }
    assert_equal %w[admin employee employee], memberships.values_at("boss@contoso.test", "ann@contoso.test", "bob@contoso.test").map { |m| m.role.to_s }
    assert memberships.values.all?(&:invited?)
    assert_empty User.find_by!(email: "boss@contoso.test").user_identities
  end

  test "saving a company invites whoever its form lists" do
    sign_in_as(@admin)

    assert_enqueued_emails 1 do
      patch admin_company_path(@company), params: {
        company: { name: "Northwind Traders", invite_emails: "ann@example.com", invite_role: "admin" }
      }
    end

    assert_redirected_to new_admin_company_invitation_path(@company)
    assert_equal "Northwind Traders", @company.reload.name
    ann = @company.company_memberships.joins(:user).find_by!(users: { email: "ann@example.com" })
    assert { ann.invited? && ann.admin? }
  end

  test "a new company without invitations opens on its page, as before" do
    sign_in_as(@admin)

    post admin_companies_path, params: { company: attributes_for(:company, name: "Contoso") }

    assert_redirected_to admin_company_path(Company.find_by!(name: "Contoso"))
  end
end
