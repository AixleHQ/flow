# frozen_string_literal: true

module Admin
  # Platform feature flags (config/feature_flags.yml): what each one resolves
  # to, its global value and turning it off everywhere. Every change goes
  # through FeatureFlags::Admin. Not an Administrate resource: most declared
  # flags have no row.
  class FeatureFlagsController < Admin::ApplicationController
    COMPANY_MATCHES = 20

    before_action :set_definition, only: %i[show update turn_off_everywhere]

    rescue_from FeatureFlags::WriteRefused do |error|
      target = FeatureFlags.registry.declared?(params[:key]) ? admin_feature_flag_path(params[:key]) : admin_feature_flags_path
      redirect_to target, alert: error.message, status: :see_other
    end

    def index
      @overview = FeatureFlags::Overview.new

      render layout: "administrate/application"
    end

    def show
      @overview = FeatureFlags::Overview.new
      @row = @overview.row(@definition.key)
      flag = @row.flag
      @overrides = flag ? flag.overrides.includes(:company, :created_by).order(updated_at: :desc) : FeatureFlagOverride.none
      @audits = flag ? Audit.where(auditable: flag).includes(:user, :associated).order(id: :desc) : Audit.none
      @company_query = params[:company_query].to_s.strip
      @company_matches = matching_companies(@company_query)

      render layout: "administrate/application"
    end

    def update
      case params[:value]
      when "on", "off" then FeatureFlags::Admin.set_global(@definition.key, params[:value] == "on", **write_context)
      when "default" then FeatureFlags::Admin.clear_global(@definition.key, **write_context)
      else raise FeatureFlags::WriteRefused, "Choose on, off or use default"
      end

      redirect_to admin_feature_flag_path(@definition.key), notice: "Global value of #{@definition.key} saved.", status: :see_other
    end

    def turn_off_everywhere
      FeatureFlags::Admin.turn_off_everywhere(@definition.key, **write_context)

      redirect_to admin_feature_flag_path(@definition.key), notice: "#{@definition.key} is off everywhere.", status: :see_other
    end

    private

    def set_definition
      @definition = FeatureFlags.registry.fetch(params[:key])
    rescue FeatureFlags::UnknownFlag
      raise ActiveRecord::RecordNotFound, "no feature flag #{params[:key]}"
    end

    def write_context = { actor: true_user, reason: params[:reason], request: request }

    def matching_companies(query)
      return Company.none if query.empty?

      Company.where("name ILIKE :q OR display_name ILIKE :q", q: "%#{Company.sanitize_sql_like(query)}%")
             .order(:name).limit(COMPANY_MATCHES)
    end
  end
end
