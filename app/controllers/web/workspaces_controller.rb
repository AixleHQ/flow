# frozen_string_literal: true

# Signing a company up for yourself. Only where we host and invoice: a
# self-hosted operator creates companies from the admin, and a Marketplace
# installation belongs to the customer who bought it — in neither does a stranger
# get to conjure a workspace.
#
# Two ways in, one form. Someone already signed in has an address we did not take
# their word for, so their answers are written straight away. A stranger's are
# not written at all: they go out in a signed link to the address they typed, and
# opening it is the proof (#confirm).
class Web::WorkspacesController < Web::ApplicationController
  layout "inertia"

  EMAIL_SIGNUP_UNAVAILABLE =
    "This installation does not accept emailed sign-in links, so sign in first and the form will be waiting."

  skip_before_action :enforce_onboarding
  skip_before_action :enforce_workspace
  before_action :require_self_serve_signup
  before_action :require_no_membership

  # Anyone may make us send mail to an address of their choosing here, which is
  # a spam gun if left open. Inert in test, where the cache is a null store.
  rate_limit to: 10, within: 1.hour, only: :create, by: -> { request.remote_ip }, if: -> { !signed_in? },
             with: -> { refuse(base: "Too many attempts. Try again in an hour.") }

  def new
    render inertia: "Workspaces/NewPage", props: props
  end

  def create
    form = WorkspaceOnboardingForm.new(user: current_user, **workspace_params.to_h.symbolize_keys)
    return refuse(**form.errors.to_hash(true)) unless form.valid?

    return refuse(base: EMAIL_SIGNUP_UNAVAILABLE) unless signed_in? || emailed_proof_accepted?

    signed_in? ? create_now(form) : send_confirmation(form)
  end

  # The other half of a stranger's signup. The link carries the answers, so
  # nothing was reserved in the meantime and a link never opened leaves nothing
  # behind.
  def confirm
    return refuse(base: EMAIL_SIGNUP_UNAVAILABLE) unless emailed_proof_accepted?

    answers = WorkspaceSignupTicket.decode(params[:token])
    return refuse(base: "That link has expired. Fill the form in again and we will send a new one.") if answers.nil?

    form = WorkspaceOnboardingForm.new(**answers)
    existing = User.find_by(email: form.email)
    return refuse(base: "That account cannot create a workspace.") if existing&.deleted?
    return refuse(base: "You already belong to a workspace.") if existing&.company_memberships&.exists?

    owner = form.owner_for(existing)
    return refuse(**form.errors.to_hash(true)) unless form.save(owner)

    # Opening a link sent to that address is the magic-link proof, and recording
    # it is what makes the session one the new company's policy accepts. Without
    # it the person lands on step-up holding no credential to step up with.
    sign_in(owner, provider: IdentityProvider.deployment!("magic_link"))
    redirect_to onboarding_path, notice: "#{form.company.name} is ready"
  end

  private

  # Signing a stranger up rests entirely on the emailed link, so an installation
  # that does not accept emailed links cannot offer this at all.
  def emailed_proof_accepted?
    Auth::PolicyResolver.deployment_allowlist_kinds.include?("magic_link")
  end

  def create_now(form)
    return refuse(**form.errors.to_hash(true)) unless form.save(current_user)

    redirect_to onboarding_path, notice: "#{form.company.name} is ready"
  end

  def send_confirmation(form)
    WorkspaceSignupMailer.confirm(
      email: form.email, workspace_name: form.name, token: ticket_for(form)
    ).deliver_later
    redirect_to new_workspace_path(sent: form.email)
  end

  def ticket_for(form)
    WorkspaceSignupTicket.issue(name: form.name, email: form.email, max_sessions: form.max_sessions)
  end

  def refuse(**errors)
    redirect_to new_workspace_path, inertia: { errors: errors }
  end

  def props
    form = WorkspaceOnboardingForm.new(user: current_user)
    {
      suggested_domain: form.email_domain,
      suggested_name: form.email_domain.to_s.split(".").first&.capitalize,
      default_max_sessions: requested_sessions || SessionAdmissionPolicy.scope_default("Project"),
      # Present once a link has gone out, which is the whole of that screen: the
      # address it went to, so the person knows which inbox to open.
      sent_to: params[:sent].presence,
      # Carried from the sign-in screen, where the address was typed first.
      suggested_email: safe_email_param,
      # A stranger types the address they will own the workspace with; someone
      # signed in has already proved theirs and is not asked again.
      needs_email: !signed_in?
    }
  end

  # The /how-it-works calculator works out how many queues a workload needs and
  # sends the visitor here with that number, so the form opens on the figure they
  # were just shown rather than on the installation default.
  # Echoed back into the form only when it actually looks like an address, so the
  # page cannot be made to display arbitrary text through a link.
  def safe_email_param
    email = params[:email].to_s.strip.downcase
    email.match?(URI::MailTo::EMAIL_REGEXP) ? email : nil
  end

  def requested_sessions
    count = params[:sessions].to_i
    count.positive? ? count : nil
  end

  def workspace_params
    params.fetch(:workspace, {}).permit(:name, :email, :email_domain, :max_sessions)
  end

  def require_self_serve_signup
    redirect_to login_path(error: "no_workspace") unless Deployment.self_serve_signup?
  end

  # Someone who already belongs somewhere has no business here, and a super admin
  # belongs nowhere on purpose. A stranger is exactly who this is for.
  def require_no_membership
    return unless signed_in?
    return if !current_user.super_admin? && !current_user.company_memberships.exists?

    redirect_to root_path
  end
end
