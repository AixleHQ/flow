# frozen_string_literal: true

require "test_helper"

module Slack
  class InstallResolverTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
    end

    def install(team_id, project: nil, status: :active)
      Integration.create!(provider: :slack, company: @company, project: project, connected_by: @user,
        name: "Workspace #{team_id}", status: status, settings: { "team_id" => team_id })
    end

    def resolve(**args)
      Slack::InstallResolver.call(company_id: @company.id, project_id: @project.id, **args)
    end

    test "without a Slack origin, the company's earliest-connected workspace, however the rows are stored" do
      first = install("T1")
      install("T2")
      # An update rewrites the older row behind the newer one, so a query without
      # an order would usually return the newer install first.
      first.update!(name: "Renamed")

      assert_equal first, resolve
    end

    test "an install bound to the project wins over the company-wide ones" do
      install("T1")
      bound = install("T2", project: @project)

      assert_equal bound, resolve
    end

    test "a Slack-born run answers through the workspace it came from" do
      install("T1")
      origin = install("T2")

      assert_equal origin, resolve(integration_id: origin.id, team_id: "T2")
    end

    test "a workspace reconnected under a new row is still found by its team" do
      install("T1")
      reconnected = install("T2")

      assert_equal reconnected, resolve(integration_id: reconnected.id + 100, team_id: "T2")
    end

    test "a Slack-born run whose workspace is gone gets nothing, never another workspace" do
      install("T1")
      gone = install("T2", status: :inactive)

      assert_nil resolve(integration_id: gone.id, team_id: "T2")
    end

    test "nothing without a company, and nothing from another company" do
      other = create(:company)
      Integration.create!(provider: :slack, company: other, connected_by: @user, name: "Theirs", status: :active)

      assert_nil Slack::InstallResolver.call(company_id: nil)
      assert_nil resolve
    end
  end
end
