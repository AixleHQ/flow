# frozen_string_literal: true

class Web::DashboardCompaniesController < Web::ApplicationController
  include DashboardViewerOnly
  include TenantDashboardCompanies
end
