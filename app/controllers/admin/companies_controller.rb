# frozen_string_literal: true

module Admin
  class CompaniesController < Admin::ApplicationController
    ACTIVE_WITHOUT_A_CUSTOMER = "cannot be active without a Stripe customer — the company pays through Checkout, " \
                                "or tick Managed by Aixle for one we carry"

    def update
      company = requested_resource
      company.assign_attributes(resource_params)
      return super unless active_without_a_customer?(company)

      company.validate
      company.errors.add(:billing_state, ACTIVE_WITHOUT_A_CUSTOMER)
      render :edit, locals: { page: Administrate::Page::Form.new(dashboard, company) }, status: :unprocessable_entity
    end

    def create
      # Extract initial admin credentials before building company
      initial_admin_email = params.dig(:company, :initial_admin_email)
      initial_admin_password = params.dig(:company, :initial_admin_password)

      # Remove virtual attributes from params before creating company
      company_params = resource_params.except(:initial_admin_email, :initial_admin_password)
      company = Company.new(company_params)
      apply_billing_terms(company)

      if company.save
        # Create initial admin user if credentials provided
        if initial_admin_email.present? && initial_admin_password.present?
          admin_user = User.new(
            email: initial_admin_email,
            password: initial_admin_password,
            password_confirmation: initial_admin_password,
            name: initial_admin_email.split("@").first.titleize, # Generate name from email
            state: "active"
          )
          admin_user.company_memberships.build(
            company: company, role: "admin", state: "active", accepted_at: Time.current
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

    private

    # Where we host, a company made here pays the way a self-serve signup does —
    # free allowance, then a card — unless it is one we carry. Left at the
    # column's `active`, it is billed with nothing to bill through: the billing
    # tab offers no Checkout, and the meter drops its minutes for want of a
    # Stripe customer. Unticking the box later does the same in Company.
    def apply_billing_terms(company)
      return unless Deployment.saas?

      if company.managed_by_aixle?
        company.session_concurrency_limit = Company::MANAGED_SESSION_LIMIT if company.session_concurrency_limit.blank?
      else
        company.billing_state = "trialing"
      end
    end

    # Where we host, a company is paid for through Stripe or carried by us. Made
    # `active` by hand with no Stripe customer, it would run with nothing to bill
    # through: free, without being ours. A rule of this form rather than of
    # Company, because the Stripe webhook and the tests move companies to
    # `active` on their own terms.
    def active_without_a_customer?(company)
      Deployment.saas? && company.billing_active? && company.billing_state_changed? &&
        !company.managed_by_aixle? && company.stripe_customer_id.blank?
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
