# frozen_string_literal: true

# Picker payload for attaching config items to a session, workflow or step.
#
# `PickerResource` (id + name) is not enough here: the UI has to tell a secret
# from a variable, because attaching a secret carries a warning that attaching a
# variable does not. Carries NO value of any kind — not even the mask.
class ConfigItemPickerResource < ApplicationResource
  typelize :number
  attribute :id do |item|
    item.id
  end

  typelize :string
  attribute :name do |item|
    item.name
  end

  typelize %w[secret variable]
  attribute :item_type do |item|
    item.item_type.to_s
  end

  typelize :string?
  attribute :description do |item|
    item.description
  end
end
