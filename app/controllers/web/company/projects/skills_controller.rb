# frozen_string_literal: true

class Web::Company::Projects::SkillsController < Web::Company::Projects::ApplicationController
  def index
    skills = Skill.visible_for_project(current_project).order(created_at: :desc)

    props = {
      project: project_props,
      skills: skills.map { |s| SkillResource.new(s).to_h },
      catalogQuery: catalog_query,
      catalogSkills: Skills::CatalogSearch.call(catalog_query).map { |c| CatalogSkillResource.new(c).to_h },
      catalogSyncedAt: CatalogSkill.maximum(:registry_synced_at)
    }

    render inertia: "Projects/Skills/SkillsPage", props: props
  end

  def create
    skill = SkillsRegistryService.install(
      params[:skill_id],
      scope: current_project,
      installs: catalog_installs(params[:skill_id])
    )
    redirect_to company_project_skills_path(current_project), notice: "Skill '#{skill.name}' installed"
  rescue SkillsRegistryService::RegistryError => e
    redirect_to company_project_skills_path(current_project), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to company_project_skills_path(current_project), alert: e.record.errors.full_messages.join(", ")
  rescue ActiveRecord::RecordNotUnique
    # Two people (or two clicks) installing the same skill at once: the unique index
    # is doing its job, and this is not a 500.
    redirect_to company_project_skills_path(current_project), alert: "That skill is already installed"
  end

  # Register a skill written by hand rather than installed from the registry.
  #
  # `name` and `description` come from the pasted frontmatter and nowhere else: the
  # Agent Skills spec requires a skill's name to equal its directory name, and a
  # second source of truth for the name is exactly how that invariant breaks.
  #
  # Validation failures come back as Inertia errors rather than a flash, so the modal
  # can show them next to the field WITHOUT discarding what the user pasted.
  def manual
    result = Skills::SkillMarkdown.parse(params[:content])

    unless result.valid?
      redirect_to company_project_skills_path(current_project),
                  inertia: { errors: { content: result.error_sentence } }
      return
    end

    skill = current_project.skills.create!(
      name: result.name,
      title: result.frontmatter["title"].presence || result.name,
      description: result.description,
      content: result.content,
      origin: :manual
    )
    redirect_to company_project_skills_path(current_project), notice: "Skill '#{skill.name}' added"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to company_project_skills_path(current_project),
                inertia: { errors: { content: e.record.errors.full_messages.join(", ") } }
  rescue ActiveRecord::RecordNotUnique
    redirect_to company_project_skills_path(current_project),
                inertia: { errors: { content: "A skill with that name already exists in this project" } }
  end

  # Edit a hand-written skill. Registry skills are excluded on purpose: their content
  # belongs to the source they name, an edit would silently diverge from it, and the
  # next install would clobber the edit anyway.
  #
  # A rename is allowed — the name comes from the frontmatter, as on create — but note
  # that a session already running keeps the old directory; the next session gets the
  # new one.
  def update
    skill = Skill.visible_for_project(current_project).find_by(id: params[:id])

    unless skill
      redirect_to company_project_skills_path(current_project), alert: "Skill not found"
      return
    end

    unless skill.manual?
      redirect_to company_project_skills_path(current_project),
                  alert: "Registry skills cannot be edited — remove it and add your own instead"
      return
    end

    result = Skills::SkillMarkdown.parse(params[:content])

    unless result.valid?
      redirect_to company_project_skills_path(current_project),
                  inertia: { errors: { content: result.error_sentence } }
      return
    end

    skill.update!(
      name: result.name,
      title: result.frontmatter["title"].presence || result.name,
      description: result.description,
      content: result.content
    )
    redirect_to company_project_skills_path(current_project), notice: "Skill '#{skill.name}' updated"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to company_project_skills_path(current_project),
                inertia: { errors: { content: e.record.errors.full_messages.join(", ") } }
  rescue ActiveRecord::RecordNotUnique
    redirect_to company_project_skills_path(current_project),
                inertia: { errors: { content: "A skill with that name already exists in this project" } }
  end

  def destroy
    skill = Skill.visible_for_project(current_project).find_by(id: params[:id])

    unless skill
      redirect_to company_project_skills_path(current_project), alert: "Skill not found"
      return
    end

    skill.destroy
    redirect_to company_project_skills_path(current_project), notice: "Skill removed"
  end

  private

  def catalog_query
    params[:catalog_q].to_s.strip
  end

  # The download endpoint reports no install count, so the figure comes from the
  # catalog row the user clicked — the search endpoint is the only place it exists.
  def catalog_installs(skill_id)
    CatalogSkill.find_by(registry_id: skill_id.to_s)&.installs
  end
end
