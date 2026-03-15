# frozen_string_literal: true

module Admin
  class MCPServersController < Admin::ApplicationController
    def resource_class
      MCPServer
    end

    def default_sorting_attribute
      :id
    end

    def default_sorting_direction
      :desc
    end
  end
end
