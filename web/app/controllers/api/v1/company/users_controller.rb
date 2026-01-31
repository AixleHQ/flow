# frozen_string_literal: true

module Api
  module V1
    module Company
      class UsersController < ApplicationController
        def index
          users = current_company.users.ransack(params[:q]).result
          respond_with paginate(users)
        end

        def create
          user = current_company.users.create(create_user_params)
          respond_with user
        end

        def update
          user = current_company.users.find(params[:id])
          user.update(update_user_params)
          respond_with user
        end

        def destroy
          user = current_company.users.find(params[:id])
          user.destroy
          head :no_content
        end

        private

        # Roles that company admins can assign (super_admin is excluded)
        ASSIGNABLE_ROLES = %w[employee admin].freeze

        def create_user_params
          params.require(:user).permit(:email, :name, :role, :state_event).merge(inviter: current_user).tap do |p|
            p[:role] = p[:role].presence_in(ASSIGNABLE_ROLES) || "employee"
          end
        end

        def update_user_params
          params.require(:user).permit(:email, :name, :role, :state_event).tap do |p|
            p.delete(:role) unless p[:role].presence_in(ASSIGNABLE_ROLES)
          end
        end
      end
    end
  end
end
