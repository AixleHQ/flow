# frozen_string_literal: true

# One project's row on the profile's "Connected accounts" tab: the two switches
# that decide what agents may do with the user's account there. The object may be
# an unsaved ActAsConsent, which stands for "both off".
class ActAsConsentResource < ApplicationResource
  typelize_from ActAsConsent

  attributes :project_id, :in_own_tasks, :in_others_tasks

  typelize "string"
  attribute :project_name do |consent|
    consent.project.name
  end
end
