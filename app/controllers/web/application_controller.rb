# frozen_string_literal: true

class Web::ApplicationController < ApplicationController
  include AuthConcern
  include PaginationConcern

  wrap_parameters false

  before_action :negotiate_format
  before_action :match_partial_keys_in_either_case
  before_action :redirect_super_admin_to_admin_panel
  # Before the auth policy: a person with no company at all has no policy to
  # satisfy, and one screen to be on until they do.
  before_action :enforce_workspace
  # AD-5: a company stays current only while this session satisfies its
  # effective auth set. Runs before onboarding — entering the company at all is
  # the more fundamental question.
  before_action :enforce_company_auth_policy
  before_action :enforce_onboarding

  inertia_share do
    shared = {
      flash: flash.to_hash,
      settings: {
        env: Rails.env,
        domain: Settings.domain,
        # Only exposed to signed-in users (F8) — nil for anonymous visitors so it
        # no longer ships in the /login data-page. Low sensitivity (a GitHub App
        # slug is public in its install URL), just not anonymous-facing.
        github_app_slug: signed_in? ? Settings.github.app_slug : nil,
        app_version: Settings.app.version,
        # Public by design (a browser Sentry DSN is write-only ingest for one
        # project and must ship to the client anyway). Kept in props — not baked
        # at build — so it stays runtime-configurable via ENV. Real abuse defense
        # is Sentry-side allowed-domains + spike protection, not hiding the DSN.
        sentry_frontend_dsn: Settings.sentry.frontend_dsn,
        sentry_traces_sample_rate: Settings.sentry.traces_sample_rate.to_f,
        # Whether a stranger may sign a company up here, which is also what
        # decides that /how-it-works — the page that sells it — exists at all.
        self_serve_signup: Deployment.self_serve_signup?,
        feedback_enabled: signed_in? && Feedback.enabled?
      },
      # Flags declared `client: true` only, read by useFeatureFlag. Always
      # re-evaluated, so a partial reload picks up a flip. Anonymous pages get
      # them too, resolved with no company: the payload never carries more than
      # flags already meant for any browser.
      features: InertiaRails.always { FeaturesResource.new(current_company).to_h }
    }

    if signed_in?
      shared.merge(
        current_user: InertiaRails.always {
          # current_membership comes from AuthConcern (session-validated); the
          # resource needs it to render current_company/current_role.
          CurrentUserResource.new(current_user, params: { current_membership: current_membership }).to_h
        },
        # Sidebar projects are the CURRENT company's slice only — a
        # dual-membership user sees the other company's projects after a switch.
        projects: InertiaRails.always {
          scope = current_company ? Project.for_user(current_user).for_company(current_company) : Project.none
          # Only what the switcher shows (SharedProject in shared/ui/types.ts). The
          # full ProjectResource ran five counting subqueries per project on every
          # page — cable-triggered reloads included — for fields nothing here read.
          # Favorites lead the list (same order as /company/projects); the
          # favorite flag drives the read-only star mark in the switcher.
          favorite_project_ids = current_user.project_favorites.pluck(:project_id).to_set
          scope.with_state(:active)
               .favorites_first_for(current_user)
               .order(:name)
               .pluck(:id, :name, :slug, :state)
               .map do |id, name, slug, state|
                 { id: id, name: name, slug: slug, state: state, favorite: favorite_project_ids.include?(id) }
               end
        },
        # Present only while a free trial is running or spent, so every screen
        # can say so rather than leaving a person to work out why nothing starts.
        trial: InertiaRails.always { trial_share },
        marketplace: InertiaRails.always { marketplace_share }
      )
    else
      shared
    end
  end

  private

  # Nil everywhere but the hosted product, and nil there for a company somebody
  # is paying for.
  # What a workspace AWS bills is told while it is stopped. The allowance
  # banner withholds itself from this payer -- it has no allowance and the card
  # it offers is refused -- so without this such a workspace says nothing at
  # all, and sessions that never start look like a fault.
  #
  # Nothing while it is running: the subscription lives in the buyer's AWS
  # account and there is no number of ours worth putting on every screen.
  def marketplace_share
    return nil unless Deployment.saas?
    return nil if current_company.nil? || current_company.billing_active?
    return nil unless current_company.billing_payer.aws_marketplace?

    { status: current_company.billing_status, listing_url: ::Billing::MarketplaceListing.listing_url }
  end

  def trial_share
    return nil unless Deployment.saas?
    return nil if current_company.nil? || current_company.billing_active?
    # Everything below is the free allowance and the card that replaces it,
    # and an AWS Marketplace workspace has neither: no allowance was ever
    # offered, and Checkout refuses that payer anyway, so the button led to a
    # refusal. What such a workspace should be told instead is its own banner,
    # which does not exist yet (§10).
    return nil if current_company.billing_payer.aws_marketplace?

    {
      state: current_company.billing_state,
      # Why a blocked company is blocked, which decides what undoes it: a card
      # for a spent trial or an ended subscription, the open invoice for a
      # failed payment.
      status: current_company.billing_status,
      days: ::Billing::Trial.length_in_days(current_company),
      days_left: ::Billing::Trial.days_left(current_company),
      last_day: ::Billing::Trial.last_day(current_company).iso8601,
      # Whether there is a card to add at all. An installation with no Stripe
      # credentials must offer a button that leads somewhere, so it offers none.
      can_pay: ::Billing::StripeClient.new.configured?
    }
  end

  # Inertia picks a partial reload's props by the server's own key names, before
  # config/initializers/inertia.rb camelizes them on the way out. Most server
  # keys are snake_case and every client-side name is camelCase, so a page that
  # reloaded `only: ['editBranches']` received nothing. Each requested key is
  # offered in both spellings.
  PARTIAL_KEY_HEADERS = %w[X-Inertia-Partial-Data X-Inertia-Partial-Except X-Inertia-Reset].freeze

  def match_partial_keys_in_either_case
    PARTIAL_KEY_HEADERS.each do |name|
      keys = request.headers[name].to_s.split(",").compact_blank
      next if keys.empty?

      request.headers[name] = keys.flat_map { |key| key_spellings(key) }.uniq.join(",")
    end
  end

  def key_spellings(key)
    segments = key.split(".")
    [ key, segments.map(&:underscore).join("."), segments.map { |s| s.camelize(:lower) }.join(".") ]
  end

  # Redirects to step-up rather than signing the user out (AD-5). Super admins
  # bypass every company policy surface (AD-19), which PolicyResolver already
  # answers, but the guard short-circuits here too so no query runs for them.
  def enforce_company_auth_policy
    return unless signed_in?
    return if current_user.super_admin?
    return if company_auth_policy_satisfied?

    redirect_to step_up_path
  end

  def negotiate_format
    return if request.headers["X-Inertia"].present?

    if request.content_type&.include?("json")
      request.format = :json
    elsif !request.format.html?
      # Bots/scanners hit paths like /login.jpg, which Rails negotiates to a
      # non-HTML format and Inertia then 500s on (no .jpeg template — Sentry
      # PALAD-AI-RAILS-1N). Web pages are HTML-only, so coerce to HTML.
      request.format = :html
    end
  end

  def redirect_super_admin_to_admin_panel
    return unless signed_in? && current_user.super_admin?

    # /admin is Administrate — a classic server-rendered page, not an Inertia
    # screen. During an Inertia visit (e.g. the redirect chain right after
    # login), a plain `redirect_to` makes the client receive a non-Inertia
    # HTML response it can't process, so Inertia dumps it into its error modal
    # (the admin page shown in a box over a dark backdrop, URL stuck on /login).
    # `inertia_location` replies 409 + X-Inertia-Location so the client does a
    # full-page visit to /admin instead.
    if request.headers["X-Inertia"].present?
      inertia_location(admin_root_path)
    else
      redirect_to admin_root_path
    end
  end

  # A signed-in person with no company anywhere has one thing to do, and every
  # other screen would render empty for them. Only where we host: elsewhere a
  # workspace is made in the admin, and someone with no membership is a refusal
  # rather than a signup.
  def enforce_workspace
    return unless Deployment.self_serve_signup?
    return unless signed_in?
    return if current_user.super_admin?
    # Already resolved for this request, so the common case — a person who
    # belongs somewhere — costs nothing. The count below runs only for the few
    # who have no current membership, rather than once per request for everyone.
    return if current_membership
    return if current_user.company_memberships.exists?
    return if request.path == new_workspace_path

    redirect_to new_workspace_path
  end

  def enforce_onboarding
    return unless signed_in?
    # Onboarding is per company: completing it for company A says nothing about
    # company B, which needs its own role, agents and (separately billed)
    # credential. Super admins have no membership and no onboarding.
    return if current_membership.nil?
    return if current_membership.onboarding_completed?

    redirect_to onboarding_path unless request.path == onboarding_path
  end
end
