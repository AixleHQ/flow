# frozen_string_literal: true

class Web::Company::Projects::SkillsController < Web::Company::Projects::ApplicationController
  def index
    skills = Skill.visible_for_project(current_project).order(created_at: :desc)

    props = {
      project: project_props,
      skills: skills.map { |s| SkillResource.new(s).to_h },
      registryQuery: params[:q].to_s,
      registryResults: search_registry(params[:q])
    }

    render inertia: "Projects/Skills/SkillsPage", props: props
  end

  def create
    skill = SkillsRegistryService.install(params[:skill_id], scope: current_project)
    redirect_to company_project_skills_path(current_project), notice: "Skill '#{skill.name}' installed"
  rescue SkillsRegistryService::RegistryError => e
    redirect_to company_project_skills_path(current_project), alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to company_project_skills_path(current_project), alert: e.record.errors.full_messages.join(", ")
  end

  def destroy
    skill = Skill.visible_for_project(current_project).find_by(id: params[:id])

    unless skill
      redirect_to company_project_skills_path(current_project), alert: "Skill not found"
      return
    end

    if skill.scope_type == "Company"
      redirect_to company_project_skills_path(current_project),
                  alert: "Company skills can only be removed from Company Skills by a company admin"
      return
    end

    skill.destroy
    redirect_to company_project_skills_path(current_project), notice: "Skill removed"
  end

  private

  def search_registry(query)
    return [] if query.blank?

    SkillsRegistryService.search(query)
  end
end
