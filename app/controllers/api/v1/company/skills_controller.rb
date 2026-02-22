# frozen_string_literal: true

module Api
  module V1
    module Company
      class SkillsController < ApplicationController
        def index
          company_skills = current_company.skills.ransack(params[:q]).result.to_a
          internal = Skill.internal_skills.to_a
          internal.each { |s| s.define_singleton_method(:scope_indicator) { "internal" } }
          skills = (internal + company_skills).sort_by(&:name)
          respond_with skills, each_serializer: SkillSerializer
        end

        def create
          skill = current_company.skills.create(skill_params)
          respond_with skill, serializer: SkillSerializer
        end

        def update
          skill = current_company.skills.find(params[:id])
          skill.update(skill_params)
          respond_with skill, serializer: SkillSerializer
        end

        def destroy
          skill = current_company.skills.find(params[:id])
          skill.destroy
          respond_with skill
        end

        private

        def skill_params
          params.require(:skill).permit(:name, :title, :content, :description)
        end
      end
    end
  end
end
