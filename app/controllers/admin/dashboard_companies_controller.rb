# frozen_string_literal: true

module Admin
  # What the dashboard fetches for its selected days (docs/design/tenant-usage-report.md
  # §7.1): every company's p95 wait for the table, and one company's queue in
  # detail when it is opened.
  class DashboardCompaniesController < Admin::ApplicationController
    rescue_from Date::Error, with: -> { head :bad_request }

    def waits
      from, to = days
      return head :bad_request if to < from

      render json: Usage::TenantWaits.call(from: from, to: to).map { |row| camelized(row) }
    end

    def show
      company = Company.find(params[:id])
      from, to = days
      return head :bad_request if to < from

      render json: camelized(Usage::CompanyBreakdown.new(company, from: from, to: to).to_h)
    end

    private

    def days = [ Date.iso8601(params.require(:from)), Date.iso8601(params.require(:to)) ]

    def camelized(hash) = hash.deep_transform_keys { |key| key.to_s.camelize(:lower) }
  end
end
