# frozen_string_literal: true

module Admin
  class CompaniesController < Admin::ApplicationController
    def create
      # Extract initial admin credentials before building company
      initial_admin_email = params.dig(:company, :initial_admin_email)
      initial_admin_password = params.dig(:company, :initial_admin_password)

      # Remove virtual attributes from params before creating company
      company_params = resource_params.except(:initial_admin_email, :initial_admin_password)
      company = Company.new(company_params)

      if company.save
        # Create initial admin user if credentials provided
        if initial_admin_email.present? && initial_admin_password.present?
          admin_user = User.new(
            email: initial_admin_email,
            password: initial_admin_password,
            password_confirmation: initial_admin_password,
            name: initial_admin_email.split("@").first.titleize, # Generate name from email
            company_id: company.id,
            role: "admin",
            state: "active",
            onboarding_state: "step1"
          )

          unless admin_user.save
            # If admin user creation fails, delete the company and show errors
            company.destroy
            flash[:error] = "Failed to create admin user: #{admin_user.errors.full_messages.join(', ')}"
            render :new, locals: { page: Administrate::Page::Form.new(dashboard, company) }, status: :unprocessable_entity
            return
          end
        end

        redirect_to(
          [ namespace, company ],
          notice: translate_with_resource("create.success"),
        )
      else
        render :new, locals: { page: Administrate::Page::Form.new(dashboard, company) }, status: :unprocessable_entity
      end
    end

    # Override this method to specify custom lookup behavior.
    # This will be used to set the resource for the `show`, `edit`, and `update`
    # actions.
    #
    # def find_resource(param)
    #   Foo.find_by!(slug: param)
    # end

    # The result of this lookup will be available as `requested_resource`

    # Override this if you have certain roles that require a subset
    # this will be used to set the records shown on the `index` action.
    #
    # def scoped_resource
    #   if current_user.super_admin?
    #     resource_class
    #   else
    #     resource_class.with_less_stuff
    #   end
    # end

    # See https://administrate-demo.herokuapp.com/customizing_controller_actions
    # for more information
  end
end
