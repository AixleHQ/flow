# frozen_string_literal: true

module ContextBuilders
  class Resources < Base
    def applicable?
      session.repository_ids.present? ||
        session.input_asset_ids.present? ||
        session.skill_ids.present?
    end

    def build
      parts = []
      parts << build_repositories if session.repository_ids.present?
      parts << build_assets if session.input_asset_ids.present?
      parts << build_skills if session.skill_ids.present?

      return [] if parts.compact.empty?

      [ section(
        tag: "available-resources",
        priority: :info,
        content: parts.compact.join("\n\n")
      ) ]
    end

    private

    def build_repositories
      repos = Repository.where(id: session.repository_ids).to_a
      return nil if repos.empty?

      failed = (session.metadata || {}).fetch("failed_repos", []).map { |f| f["id"] }
      cloned = repos.reject { |r| failed.include?(r.id) }
      return nil if cloned.empty?

      lines = [ "## Available Repositories" ]
      lines << ""
      lines << "The following code repositories have been cloned into this session:"
      lines << ""
      lines << "| ID | Repository | Path | Branch | Purpose |"
      lines << "|---|---|---|---|---|"
      cloned.each do |repo|
        purpose = repo.purpose.presence || "—"
        lines << "| #{repo.id} | #{repo.full_name} | /workspace/repo/#{repo.repo_name} | #{repo.source_branch} | #{purpose} |"
      end
      lines << ""
      lines << "Use the repository **ID** when calling tools that require a `repository_id` parameter."
      lines.join("\n")
    end

    def build_assets
      assets = Asset.where(id: session.input_asset_ids).to_a
      return nil if assets.empty?

      lines = [ "## Input Assets (pre-loaded in /workspace/assets/)" ]
      lines << ""
      assets.each do |asset|
        folder = asset.folder.present? ? "#{asset.folder}/" : ""
        lines << "- **#{asset.name}** (id: #{asset.id}) → `/workspace/assets/#{folder}#{asset.name}`"
      end
      lines.join("\n")
    end

    def build_skills
      skills = Skill.where(id: session.skill_ids).to_a
      return nil if skills.empty?

      if adapter.includes_skills_in_context?
        build_skills_full(skills)
      else
        build_skills_summary(skills)
      end
    end

    def build_skills_full(skills)
      lines = [ "## Skills" ]
      lines << ""
      skills.each do |skill|
        next if skill.content.blank?

        lines << "### #{skill.title.presence || skill.name}"
        lines << ""
        lines << skill.content
        lines << ""
      end
      lines.join("\n")
    end

    def build_skills_summary(skills)
      lines = [ "## Skills" ]
      lines << ""
      skills.each do |skill|
        next if skill.content.blank?

        title = skill.title.presence || skill.name
        source = skill.source.present? ? " (#{skill.source})" : ""
        desc = skill.description.presence
        lines << "- **#{title}**#{source}#{desc ? ": #{desc}" : ""}"
      end
      lines.join("\n")
    end

    def adapter
      @adapter ||= AgentCredentialsService.for(session.agent_type).adapter
    end
  end
end
