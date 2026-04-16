# frozen_string_literal: true

class CompanyResource < ApplicationResource
  attributes :id, :name, :email_domain, :logo_url, :primary_color, :secondary_color
end
