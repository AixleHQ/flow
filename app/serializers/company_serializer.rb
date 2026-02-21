class CompanySerializer < ApplicationSerializer
  attributes :id, :name, :email_domain, :logo_url, :primary_color, :secondary_color
end
