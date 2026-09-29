# frozen_string_literal: true

module Versions
  module Snapshots
    class Agent < Base
      FIELDS = %w[name title icon persona communication_style principles source].freeze
      EXCLUDED = %w[id scope_type scope_id project_id company_id archived_at current_version_number
                    created_at updated_at].freeze
    end
  end
end
