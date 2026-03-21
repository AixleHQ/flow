# frozen_string_literal: true

module ContextBuilders
  class BmadMethod < Base
    def applicable?
      session.bmad_enabled? && !bmad_install_failed?
    end

    def build
      [
        section(
          tag: "bmad-method",
          priority: :info,
          content: build_bmad_context
        )
      ]
    end

    private

    def bmad_install_failed?
      session.context_metadata&.dig("bmad_install_status") == "failed"
    end

    def build_bmad_context
      lines = []
      lines << "## BMAD Method"
      lines << ""
      lines << "This session has **BMAD Method** enabled. BMAD provides AI-native project management workflows, slash-commands, and structured artifact generation."
      lines << ""
      lines << "### BMAD Files"
      lines << ""
      lines << "- **BMAD root:** `/workspace/_bmad/`"
      lines << "- **Core config:** `/workspace/_bmad/core/config.yaml`"
      lines << "- **Modules:** #{session.bmad_modules.join(', ')}"
      lines << ""
      lines << "### Output Rules"
      lines << ""
      lines << "- All BMAD-generated artifacts must be saved to `/workspace/outputs/`"
      lines << "- Follow the artifact templates and naming conventions defined in the BMAD config"
      lines << ""
      lines << "### Usage"
      lines << ""
      lines << "- Use BMAD slash-commands as defined in your agent configuration"
      lines << "- Refer to `/workspace/_bmad/` for available agents, workflows, and templates"
      lines << "- Generated documents and artifacts go to `/workspace/outputs/`"
      lines.join("\n")
    end
  end
end
