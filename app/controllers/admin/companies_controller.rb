# frozen_string_literal: true

module Admin
  class CompaniesController < Admin::ApplicationController
    # Saved here rather than through Administrate's update, which would assign
    # the form again over a trial started below.
    def update
      company = requested_resource
      company.assign_attributes(resource_params)
      new_trial = restarted_without_a_customer?(company)
      start_new_trial(company) if new_trial

      if company.save
        notice = new_trial || company.trial_last_day ? trial_notice(company) : translate_with_resource("update.success")
        redirect_with_invitations(company, notice, fallback: after_resource_updated_path(company))
      else
        render :edit, locals: { page: Administrate::Page::Form.new(dashboard, company) }, status: :unprocessable_entity
      end
    end

    def create
      company = Company.new(resource_params)
      apply_billing_terms(company)

      unless company.save
        return render :new, locals: { page: Administrate::Page::Form.new(dashboard, company) }, status: :unprocessable_entity
      end

      notice = company.billing_trialing? ? trial_notice(company) : translate_with_resource("create.success")
      redirect_with_invitations(company, notice, fallback: [ namespace, company ])
    end

    private

    def new_resource(params = {})
      company = super
      if Deployment.requires_bounded_companies? && company.session_concurrency_limit.blank?
        company.session_concurrency_limit = Deployment.minimum_workers
      end
      company
    end

    # When the form invited anyone, the page that shows who; otherwise `fallback`.
    def redirect_with_invitations(company, notice, fallback:)
      invitations = invite_members(company)
      return redirect_to(fallback, notice: notice, status: :see_other) if invitations.empty?

      messages = invitation_flash(invitations)
      messages[:notice] = [ notice, messages[:notice] ].compact.join(" ")
      redirect_to new_admin_company_invitation_path(company), status: :see_other, **messages
    end

    # The first admin, and everyone on the invite list, gets the invitation a
    # company admin sends from Members. The admin goes first: listed again below,
    # they are only sent the link again.
    def invite_members(company)
      if company.initial_admin_email.present?
        admin = CompanyInvitation.call(company: company, email: company.initial_admin_email, role: "admin")
      end
      members = CompanyInvitation.invite_all(company: company, addresses: company.invite_emails, role: company.invite_role)
      [ admin, *members ].compact
    end

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

    # Where we host, a company is paid for through Stripe or carried by us. Set
    # running by hand with no Stripe customer — typically a blocked one an
    # operator wants to let back in — it would run with nothing to bill through:
    # free, without being ours. It gets a new free allowance instead, and needs a
    # card once that is spent. A rule of this form rather than of Company, because
    # the Stripe webhook moves companies to `active` on its own terms.
    def restarted_without_a_customer?(company)
      Deployment.saas? && company.billing_state_changed? && !company.billing_blocked? &&
        !company.managed_by_aixle? && company.stripe_customer_id.blank?
    end

    def start_new_trial(company)
      company.billing_state = "trialing"
      company.trial_started_at = Time.current
      company.trial_hours = Billing::Trial.default_hours
    end

    def trial_notice(company)
      "#{company.name} is on a trial until the end of #{Billing::Trial.last_day(company).to_fs(:long)}, " \
        "on one worker, then it needs a card."
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
