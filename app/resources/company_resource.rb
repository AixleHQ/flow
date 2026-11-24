# frozen_string_literal: true

class CompanyResource < ApplicationResource
  attributes :id, :name, :slug, :email_domain, :logo_url, :primary_color, :secondary_color
end
