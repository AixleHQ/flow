# frozen_string_literal: true

module Admin
  class DashboardCompaniesController < Admin::ApplicationController
    include TenantDashboardCompanies
  end
end
