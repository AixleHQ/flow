# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class CollaboratorsController < ApplicationController
          def index
            users = current_project.member_users
            respond_with paginate(users)
          end

          def create
            user = current_company.users.find(collaborator_params[:user_id])
            collaborator = current_project.project_collaborators.create(user: user)

            if collaborator.persisted?
              respond_with user, status: :created
            else
              render json: { errors: collaborator.errors.messages }, status: :unprocessable_entity
            end
          end

          def destroy
            if params[:id].to_i == current_user.id
              render json: { errors: { base: [ "Cannot remove yourself from the project" ] } }, status: :unprocessable_entity
              return
            end

            current_project.project_collaborators.find_by!(user_id: params[:id]).destroy
            head :no_content
          end

          private

          def collaborator_params
            params.require(:collaborator).permit(:user_id)
          end
        end
      end
    end
  end
end
