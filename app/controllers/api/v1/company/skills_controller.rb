# frozen_string_literal: true

module Api
  module V1
    module Company
      class SkillsController < ApplicationController
        def index
          skills = Skill.visible_for_company(current_company).ransack(params[:q]).result
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
