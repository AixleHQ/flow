# frozen_string_literal: true

namespace :project_memory do
  task context: :environment do
    @memory_project = Project.find(Integer(ENV.fetch("PROJECT_ID")))
    @memory_reviewer = User.find(Integer(ENV.fetch("REVIEWER_ID")))
    membership = @memory_reviewer.company_memberships.active.find_by(company_id: @memory_project.company_id)
    permitted = membership && !membership.viewer? && (@memory_project.owner_id == @memory_reviewer.id || membership.admin?) &&
      @memory_project.accessible_by?(@memory_reviewer)
    abort "Project memory: forbidden" unless permitted
  end

  desc "List project memory metadata for review (PROJECT_ID, REVIEWER_ID)"
  task list: :context do
    puts @memory_project.project_memories.order(:id).pluck(:id, :revision, :state, :title, :review_at).to_json
  end

  desc "Validate a pending finding (PROJECT_ID, REVIEWER_ID, MEMORY_ID, REVISION, REVIEW_FILE)"
  task validate: :context do
    memory = @memory_project.project_memories.find(Integer(ENV.fetch("MEMORY_ID")))
    path = ENV.fetch("REVIEW_FILE")
    abort "Review file exceeds 16 KiB" if File.size(path) > 16_384
    review = JSON.parse(File.read(path))
    service = ProjectMemoryService.new(memory.terminal_session, project: @memory_project)
    result = service.validate!(memory: memory, expected_revision: ENV.fetch("REVISION"),
                               evidence: review.fetch("evidence"), sources: review.fetch("sources"), reviewer: @memory_reviewer)
    puts({ id: result.id, revision: result.revision, state: result.state }.to_json)
  end

  %w[obsolete purge].each do |action|
    desc "#{action.capitalize} a finding (PROJECT_ID, REVIEWER_ID, MEMORY_ID, REVISION)"
    task action => :context do
      memory = @memory_project.project_memories.find(Integer(ENV.fetch("MEMORY_ID")))
      service = ProjectMemoryService.new(memory.terminal_session, project: @memory_project)
      service.public_send("#{action}!", memory: memory, expected_revision: ENV.fetch("REVISION"), reviewer: @memory_reviewer)
      puts({ id: memory.id, action: action }.to_json)
    end
  end

  desc "Remove retrieval snapshots older than 30 days in a project (PROJECT_ID, REVIEWER_ID)"
  task prune_snapshots: :context do
    removed = MemoryRetrieval.where(project: @memory_project).where("created_at < ?", 30.days.ago).delete_all
    puts({ removed: removed }.to_json)
  end

  desc "Purge up to 100 pending/obsolete findings older than 90 days (PROJECT_ID, REVIEWER_ID)"
  task prune_findings: :context do
    records = @memory_project.project_memories.where(state: %w[pending obsolete])
      .where("updated_at < ?", 90.days.ago).order(:id).limit(100)
    count = 0
    records.each do |memory|
      ProjectMemoryService.new(memory.terminal_session, project: @memory_project)
        .purge!(memory: memory, expected_revision: memory.revision, reviewer: @memory_reviewer)
      count += 1
    end
    puts({ removed: count }.to_json)
  end

  desc "Export authorized run memory snapshots (PROJECT_ID, REVIEWER_ID, SESSION_ID); contains project data"
  task manifest: :context do
    session = @memory_project.terminal_sessions.find(Integer(ENV.fetch("SESSION_ID")))
    puts session.memory_retrievals.order(:id).pluck(:payload).to_json
  end

  desc "Export reported usage and memory estimates (PROJECT_ID, REVIEWER_ID, SESSION_IDS comma-separated; max 100)"
  task metrics: :context do
    ids = ENV.fetch("SESSION_IDS").split(",", -1)
    abort "Project memory metrics: invalid selection" unless ids.size.between?(1, 100) && ids.all? { |id| id.match?(/\A[1-9]\d*\z/) }

    puts ProjectMemoryMetrics.new(project: @memory_project, reviewer: @memory_reviewer)
      .call(session_ids: ids.map(&:to_i)).to_json
  end
end
