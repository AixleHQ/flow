# frozen_string_literal: true

# Stamps definition_digest on pre-existing custom tools so serving's
# fail-closed digest check doesn't hide them. The canonicalization mirrors
# Tool#compute_definition_digest at the time of this migration (inline copy —
# migrations must not depend on app code that keeps evolving).
class BackfillToolDefinitionDigests < ActiveRecord::Migration[8.1]
  class MigrationTool < ActiveRecord::Base
    self.table_name = "tools"
  end

  def up
    MigrationTool.reset_column_information
    MigrationTool.where(source: "db").find_each do |tool|
      payload = {
        "name" => tool.name,
        "display_name" => tool.display_name,
        "description" => tool.description,
        "command" => tool.command,
        "docker_image" => tool.docker_image,
        "input_schema" => tool.input_schema.as_json,
        "required_config_items" => tool.required_config_items.as_json
      }
      tool.update_columns(definition_digest: Digest::SHA256.hexdigest(JSON.dump(payload)))
    end
  end

  def down
    MigrationTool.where(source: "db").update_all(definition_digest: nil)
  end
end
