# frozen_string_literal: true

class Web::Company::SkillsController < Web::Company::ApplicationController
  def index
    skills = Skill.visible_for_company(current_company).order(created_at: :desc)

    props = {
      skills: skills.map { |s| SkillResource.new(s).to_h },
      registryQuery: params[:q].to_s,
      registryResults: search_registry(params[:q])
    }

    render inertia: "Company/Skills/Index", props: props
  end

  def create
    skill = SkillsRegistryService.install(params[:skill_id], scope: current_company)
    redirect_to company_skills_path, notice: "Skill '#{skill.name}' installed"
  rescue SkillsRegistryService::RegistryError => e
    redirect_to company_skills_path, alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to company_skills_path, alert: e.record.errors.full_messages.join(", ")
  end

  def destroy
    skill = current_company.skills.find(params[:id])
    skill.destroy
    redirect_to company_skills_path, notice: "Skill removed"
  end

  private

  def search_registry(query)
    return [] if query.blank?

    SkillsRegistryService.search(query)
  end
end
