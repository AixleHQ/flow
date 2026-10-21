# frozen_string_literal: true

module Admin
  # Per-company exceptions to a company-scoped feature flag, set by platform
  # staff only: company admins never see or change flags.
  class FeatureFlagOverridesController < Admin::ApplicationController
    VALUES = { "on" => true, "off" => false }.freeze

    rescue_from FeatureFlags::WriteRefused do |error|
      redirect_to flag_page, alert: error.message, status: :see_other
    end

    def create
      company = Company.find_by(id: params[:company_id])
      FeatureFlags::Admin.set_override(key, company, VALUES[params[:value]], **write_context)

      redirect_to flag_page, notice: "#{company.name} now has #{key} #{params[:value]}.", status: :see_other
    end

    def destroy
      company = Company.find(params[:company_id])
      FeatureFlags::Admin.remove_override(key, company, **write_context)

      redirect_to flag_page, notice: "Override for #{company.name} removed.", status: :see_other
    end

    private

    def key = params[:feature_flag_key]

    def flag_page
      FeatureFlags.registry.declared?(key) ? admin_feature_flag_path(key) : admin_feature_flags_path
    end

    def write_context = { actor: true_user, reason: params[:reason], request: request }
  end
end
