# frozen_string_literal: true

class UpdateBoardAttachAssetToolSchema < ActiveRecord::Migration[8.0]
  def up
    tool = Tool.find_by(name: "board_attach_asset")
    return unless tool

    tool.update!(
      description: "Attach a file to a board task by reading it from a path inside the running container.",
      input_schema: {
        type: "object",
        properties: {
          task_id: { type: "integer", description: "Board task ID" },
          name: { type: "string", description: "Attachment filename" },
          file_path: { type: "string", description: "Path inside the running container to upload" },
          tags: {
            type: "array",
            items: { type: "string" },
            description: "Optional asset tags"
          }
        },
        required: %w[task_id name file_path]
      }
    )
  end

  def down
    tool = Tool.find_by(name: "board_attach_asset")
    return unless tool

    tool.update!(
      description: "Attach a file to a board task from a container path or base64 content payload.",
      input_schema: {
        type: "object",
        properties: {
          task_id: { type: "integer", description: "Board task ID" },
          name: { type: "string", description: "Attachment filename" },
          file_path: { type: "string", description: "Path inside the running container to upload" },
          file_content: { type: "string", description: "Base64-encoded file content for small payloads" },
          tags: {
            type: "array",
            items: { type: "string" },
            description: "Optional asset tags"
          }
        },
        required: %w[task_id name]
      }
    )
  end
end
