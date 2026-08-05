# frozen_string_literal: true

require "test_helper"

class ProjectResourceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @owner = create(:user, company: @company, name: "Ada Lovelace")
    @project = create(:project, company: @company, owner: @owner)
  end

  test "members lists the owner first, with initials from their full name" do
    hash = ProjectResource.new(@project, params: { with_members: true }).to_h

    assert_equal [ { id: @owner.id, initials: "AL" } ], hash["members"]
  end

  test "members is empty unless with_members is requested, to avoid N+1 in the sidebar's project list" do
    hash = ProjectResource.new(@project).to_h

    assert_equal [], hash["members"]
  end

  test "members caps the preview at 4, owner first then collaborators" do
    collaborators = Array.new(5) { |i| create(:user, company: @company, name: "Collaborator #{i}") }
    collaborators.each { |c| @project.add_collaborator(c) }

    hash = ProjectResource.new(@project, params: { with_members: true }).to_h

    assert_equal 4, hash["members"].length
    assert_equal @owner.id, hash["members"].first[:id]
  end

  test "members_count includes the owner plus all collaborators, not just the preview" do
    collaborators = Array.new(5) { |i| create(:user, company: @company, name: "Collaborator #{i}") }
    collaborators.each { |c| @project.add_collaborator(c) }

    hash = ProjectResource.new(@project).to_h

    assert_equal 6, hash["membersCount"]
  end

  test "initials_for handles single-word names" do
    assert_equal "AC", ProjectResource.initials_for("Acme")
  end

  test "initials_for takes the first letter of the first and last word for multi-word names" do
    assert_equal "AL", ProjectResource.initials_for("Ada Lovelace")
    assert_equal "AC", ProjectResource.initials_for("Ada  Bell Curie")
  end
end
