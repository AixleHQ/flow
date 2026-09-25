# frozen_string_literal: true

module Versions
  module Snapshots
    # `files` is the whole skill directory a session writes into the container,
    # so a skill version is complete without reaching upstream.
    class Skill < Base
      FIELDS = %w[name title description content files origin source source_url package content_hash].freeze
      EXCLUDED = %w[id scope_type scope_id project_id company_id install_count archived_at
                    current_version_number created_at updated_at].freeze
    end
  end
end
