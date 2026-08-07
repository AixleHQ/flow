# frozen_string_literal: true

module PersonalTools
  # Reading a skill BEFORE installing it. `search_skill_registry` returns a
  # one-line description, and `get_skill` only works once the skill is already in
  # the project — so without this the only way to see what a third-party skill
  # actually instructs an agent to do is to install it first.
  class GetRegistrySkill < Base
    tool do
      display_name "Get Registry Skill"
      description "Fetch a registry skill's full SKILL.md without installing it, so its instructions can " \
                  "be reviewed first. Content can be thousands of tokens — narrow the choice with " \
                  "search_skill_registry and read only the candidate you are deciding on."
      audience :user
      tags :resources
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :skill_id, type: :string, description: "Registry skill id (see search_skill_registry).",
            required: true
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::SkillsPolicy, project: project)

      skill_id = params[:skill_id].to_s
      detail = SkillsRegistryService.fetch_skill_detail(skill_id)
      # Names the publisher rather than shrugging: a two-segment id from a host
      # that publishes no discovery index is a different problem from a typo.
      return error(SkillsRegistryService.unresolved_message(skill_id)) if detail.blank?

      success({ id: skill_id, source: detail["source"], slug: detail["slug"], name: detail["name"],
                content: detail["content"] }.merge(catalog_metadata(skill_id)))
    rescue SkillsRegistryService::RegistryError, SkillsRegistryService::ResolveTimeout => e
      error("Registry fetch failed: #{e.message}")
    end

    private

    # The mirrored catalog row carries what the fetched SKILL.md cannot: the
    # audit verdict. A skill that reaches out to a third-party provider is a
    # decision the caller should make with the finding in hand, not after.
    def catalog_metadata(skill_id)
      entry = CatalogSkill.find_by(registry_id: skill_id)
      return { catalog_entry: false } if entry.nil?

      { catalog_entry: true, description: entry.description, source_url: entry.registry_url,
        audited: entry.audited?, audit_warning: entry.audit_warning?,
        audit_providers: entry.audit_providers }
    end
  end
end
