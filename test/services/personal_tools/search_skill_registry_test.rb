# frozen_string_literal: true

require "test_helper"

module PersonalTools
  class SearchSkillRegistryTest < ActiveSupport::TestCase
    setup do
      @user = create(:user, :with_company)
      @company = @user.companies.first
      @project = create(:project, owner: @user, company: @company)
    end

    def execute(query: nil)
      params = { project_id: @project.id }
      params[:query] = query unless query.nil?
      SearchSkillRegistry.new(params: params, user: @user).execute
    end

    # Browsing the ranked default view is the headline capability the catalog adds;
    # an agent must be able to reach what the UI reaches, so no query is a real
    # request rather than an error.
    test "omitting the query browses the ranked catalog" do
      create(:catalog_skill, :featured, registry_id: "anthropics/skills/pdf", source: "anthropics/skills",
             slug: "pdf", description: "Fill PDF forms")

      result = execute

      assert_equal 0, result[:exit_code]
      payload = JSON.parse(result[:stdout])
      assert_nil payload["query"]
      assert_equal "anthropics/skills/pdf", payload["results"].sole["id"]
      assert_equal "Fill PDF forms", payload["results"].sole["description"]
    end

    # Same dedup the UI gets: an agent should not be handed twenty near-identical
    # skills from one collection repo.
    test "browsing returns one entry per publisher" do
      create(:catalog_skill, registry_id: "larksuite/cli/lark-doc", source: "larksuite/cli", slug: "lark-doc",
             installs: 518_503, bulk_publisher: true)
      create(:catalog_skill, registry_id: "larksuite/cli/lark-mail", source: "larksuite/cli", slug: "lark-mail",
             installs: 393_870, bulk_publisher: true)
      create(:catalog_skill, registry_id: "obra/superpowers/tdd", source: "obra/superpowers", slug: "tdd",
             installs: 188_213)

      payload = JSON.parse(execute[:stdout])

      assert_equal %w[obra/superpowers larksuite/cli], payload["results"].map { |r| r["source"] }
    end

    test "a query searches upstream" do
      SkillsRegistryService.stubs(:search).returns([ { id: "org/skills/rails", slug: "rails", name: "rails",
                                                       source: "org/skills", installs: 42 } ])

      payload = JSON.parse(execute(query: "rails")[:stdout])

      assert_equal "rails", payload["query"]
      assert_equal "org/skills/rails", payload["results"].sole["id"]
    end
  end
end
