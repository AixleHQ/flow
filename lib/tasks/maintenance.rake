# frozen_string_literal: true

namespace :maintenance do
  desc "Fail WorkflowRuns in running/paused whose Temporal execution is gone, and terminate their sessions. Set DRY_RUN=true to preview."
  task cleanup_stale_runs: :environment do
    dry_run  = ENV.fetch("DRY_RUN", "false") == "true"
    activity = Activities::Workflow::CleanupStaleRunsActivity.new

    puts "[cleanup_stale_runs] dry_run=#{dry_run}; probing runs started before #{Activities::Workflow::CleanupStaleRunsActivity::PROBE_AFTER.ago}"

    if dry_run
      %i[running paused].each do |state|
        activity.orphaned_runs(state).each do |run|
          puts "[cleanup_stale_runs] run ##{run.id} (#{run.state}, started #{run.started_at}) — execution #{run.execution_workflow_id} is gone"
        end
      end
      puts "[cleanup_stale_runs] DRY RUN complete — no changes written"
    else
      result = activity.run
      puts "[cleanup_stale_runs] done: #{result[:cleaned_running]} running and #{result[:cleaned_paused]} paused run(s) failed"
    end
  end

  desc "Encrypt MCP header/env values still held as plaintext and clear the plaintext copies. Run once nothing runs code older than the encryption change."
  task purge_plaintext_mcp_secrets: :environment do
    count = MCPServer.purge_plaintext_secrets!
    puts "[purge_plaintext_mcp_secrets] encrypted and cleared the plaintext copies of #{count} MCP server(s)"
  end

  desc "Store the files of registry skills installed before skills kept them, so their sessions stop fetching " \
       "upstream's current copy. Rate-limited upstream (60 downloads/hour): run again for the rest. LIMIT=50."
  task snapshot_skills: :environment do
    limit = ENV.fetch("LIMIT", "50").to_i
    pending = Skill.with_origin(:registry).where(files: {}).order(:id).limit(limit)
    stored = 0
    pending.each do |skill|
      detail = SkillsRegistryService.fetch_skill_detail("#{skill.source}/#{skill.package.to_s.split('@').last}")
      next puts("[snapshot_skills] ##{skill.id} #{skill.package}: no bundle (kept on skills add)") if detail&.dig("files").blank?

      skill.update!(files: detail["files"], content: detail["content"], content_hash: detail["content_hash"])
      stored += 1
    rescue SkillsRegistryService::RegistryError => e
      puts "[snapshot_skills] ##{skill.id} #{skill.package}: #{e.message}"
    end
    left = Skill.with_origin(:registry).where(files: {}).count
    puts "[snapshot_skills] stored #{stored}; #{left} registry skill(s) still install through skills add"
  end
end
