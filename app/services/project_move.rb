# frozen_string_literal: true

# Moving a project to another company of the same deployment, in place: every row
# keeps its id and only its tenant columns change, so task numbers, schedule ids
# and webhook slugs survive. Preflight says what the move will do; Mover does it.
module ProjectMove
  # What happens to people who work on the project but are not active members of
  # the target company: refuse the move, add them to the target, or take them off
  # the project.
  MEMBER_POLICIES = %w[block add drop].freeze

  class Refused < StandardError; end
end
