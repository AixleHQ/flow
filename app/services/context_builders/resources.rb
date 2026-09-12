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

      # The path the provisioner actually chose, not a path recomputed from the
      # repository name. Two repositories can share a basename, and a rename
      # upstream does not move a checkout that already exists.
      paths = RepositoryWorkspacePath.for_session(session, cloned)

      lines = [ "## Available Repositories" ]
      lines << ""
      lines << "The following code repositories have been cloned into this session:"
      lines << ""
      lines << "| ID | Repository | Path | Branch | Access | Purpose |"
      lines << "|---|---|---|---|---|---|"
      cloned.each do |repo|
        purpose = repo.purpose.presence || "—"
        access = repo.public_source? ? "public, read-only" : "integration"
        lines << "| #{repo.id} | #{repo.full_name} | #{paths[repo.id]} | #{repo.source_branch} | #{access} | #{purpose} |"
      end
      lines << ""
      lines << "Use the repository **ID** when calling tools that require a `repository_id` parameter."
      if cloned.any?(&:azure_devops?)
        lines << ""
        lines << "Azure DevOps repositories authenticate through a credential helper configured in each " \
                 "checkout, so ordinary `git fetch` and `git push` work without any extra step and keep " \
                 "working after the underlying token expires. Do not add credentials to the remote URL. " \
                 "Pull requests, review threads and Boards work items are reached with the " \
                 "`azure_devops_*` tools, not with `gh`."
      end
      if cloned.any?(&:public_source?)
        lines << ""
        lines << "Repositories marked **public, read-only** were cloned anonymously. There are no " \
                 "credentials for them: read the code, but do not try to push, open pull requests, " \
                 "or call tools that write to them."
      end
      lines.join("\n")
    end

    def build_assets
      assets = Asset.where(id: session.input_asset_ids).to_a
      return nil if assets.empty?

      lines = [ "## Input Assets (pre-loaded in /workspace/assets/)" ]
      lines << ""
      assets.each do |asset|
        folder = asset.folder.present? ? "#{asset.folder}/" : ""
        line = "- **#{asset.name}** (id: #{asset.id}) → `/workspace/assets/#{folder}#{asset.name}`"
        line += " — public link: #{asset.share_url}" if asset.shared?
        lines << line
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
