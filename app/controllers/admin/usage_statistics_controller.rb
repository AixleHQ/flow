# frozen_string_literal: true

module Admin
  class UsageStatisticsController < Admin::ApplicationController
    def default_sorting_attribute
      :id
    end

    def default_sorting_direction
      :desc
    end
  end
end
