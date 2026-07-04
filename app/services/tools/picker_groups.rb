# frozen_string_literal: true

module Tools
  # Resolves the TagCatalog group entries into concrete tool ids for one
  # project's picker: [{ tag:, label:, tool_ids: [...] }]. Only groups whose
  # tools are actually visible in this project are returned, so the picker
  # never offers an empty "Board management".
  module PickerGroups
    def self.for_project(project)
      visible = Tool.visible_for_project(project).index_by(&:name)

      Registry.ui_groups.filter_map do |group|
        ids = group[:tool_names].filter_map { |name| visible[name]&.id }
        next if ids.empty?

        { tag: group[:tag], label: group[:label], tool_ids: ids }
      end
    end
  end
end
