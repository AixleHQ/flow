# frozen_string_literal: true

# A project resource (an agent, a skill, a repository…) reports its creation
# as `resource_created` with its kind.
module AnalyticsResource
  extend ActiveSupport::Concern
  include AnalyticsTracked

  class_methods do
    def analytics_resource_type(type)
      after_create_commit { report_analytics("resource_created", type: type) }
    end
  end
end
