# frozen_string_literal: true

# Same shape as PickerResource (id + name), plus the raw `folder` value so the
# folder-aware asset picker (AssetPicker.tsx) can group results without having
# to parse `folder/name` back out of `picker_name`. Kept off the shared
# PickerResource, which also serializes Tool/Skill/Repository/Agent/MCPServer —
# none of which have a `folder`.
class AssetPickerResource < PickerResource
  typelize :string?
  attribute :folder do |asset|
    asset.folder
  end
end
