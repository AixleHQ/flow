# frozen_string_literal: true

# PickerResource plus the skill's identifier: `name` is its title, while a
# runtime that installs skills as files finds it under this name.
class SkillPickerResource < PickerResource
  typelize :string
  attribute :skill_name do |skill|
    skill.name
  end
end
