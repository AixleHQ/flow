# frozen_string_literal: true

module ContextBuilders
  class Workspace < Base
    def build
      lines = [ "## Workspace Layout" ]
      lines << ""
      lines << "Your working directory is `/workspace`."
      lines << ""
      lines << "- **`/workspace/outputs/`** — Put all results, artifacts, and deliverables here. Contents will be collected after the session."

      if session.input_asset_ids.present?
        lines << "- **`/workspace/assets/`** — Read-only reference documents provided for this task. " \
                 "Do NOT modify these files. If you need to extend an asset, copy it to `/workspace/outputs/` with the full content and edit the copy."
      end

      if session.repository_ids.present?
        lines << "- **`/workspace/repo/`** — Code repositories to work with. See the \"Available Repositories\" section for details."
      end

      [ section(
        tag: "workspace",
        priority: :important,
        content: lines.join("\n")
      ) ]
    end
  end
end
