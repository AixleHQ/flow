# frozen_string_literal: true

module Trackers
  # An external container issues live in: an Azure project, a Jira project, a
  # Linear team.
  Scope = Data.define(:id, :key, :name) do
    include Value
  end
end
