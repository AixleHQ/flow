# frozen_string_literal: true

class ProjectMemoryService
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super("Project memory: #{code.to_s.tr('_', ' ')}")
    end
  end

  def self.serves?(session)
    return false unless session

    project = session.project
    Engram::Client.configured? && session.active? && project && project.memory_enabled? &&
      session.metadata&.dig("memory_disabled") != true && project.company_id == session.company_id &&
      project.accessible_by?(session.user)
  end

  def initialize(session, project: nil, client: nil, source_verifier: ProjectMemorySourceVerifier.build)
    @session = session
    @review_project = project
    @client = client
    @source_verifier = source_verifier
  end

  def search(query:)
    raise Error, :invalid_query unless query.is_a?(String) && query.present? && query.length <= 200

    check_content!(query)
    operation do
      reserve_retrieval!
      rows = scoped.reusable.exists? ? client.search(project: namespace, query: query, limit: 20) : []
      ids = Array(rows).first(20).filter_map do |row|
        row["id"].to_s if row.is_a?(Hash) && row["project"] == namespace
      end.uniq
      indexed = scoped.reusable.where(engram_id: ids).index_by(&:engram_id)
      memories = ids.filter_map { |id| indexed[id] }.first(3).select { |memory| current?(memory) }
      results = memories.map { |memory| snapshot(memory, memory.content.first(200)) }
      settle_tokens!(results, "search")
      results
    end
  end

  def fetch(id:)
    operation do
      reserve_retrieval!
      memory = scoped.reusable.find_by(id: id)
      raise Error, :not_found unless memory && current?(memory)

      result = snapshot(memory, memory.content.first(1800))
      settle_tokens!([ result ], "detail")
      result
    end
  end

  def capture(title:, content:, topic_key:, sources:)
    operation do
      check_content!(title, content, topic_key)
      membership = @session.user.company_memberships.active.find_by(company_id: @project.company_id)
      raise Error, :forbidden if membership&.viewer?

      normalized = normalize_sources!(sources, attached: true)
      consume!(:captures, 10)
      memory = scoped.create!(title: title, content: content, topic_key: topic_key,
                              sources: normalized, terminal_session: @session, base_revision: accepted_revision(topic_key),
                              language: @project.preferred_artifacts_language, tags: [ topic_key.split("/").first ])
      { id: memory.id, revision: memory.revision, state: memory.state }
    end
  end

  def validate!(memory:, expected_revision:, evidence:, sources:, reviewer:)
    operation(reviewer: reviewer) do
      record = scoped.find_by(id: memory.id)
      raise Error, :revision_conflict unless record && record.revision == expected_revision && record.state == "pending"
      expected_base = record.validated_at? ? record.revision : record.base_revision
      raise Error, :revision_conflict unless accepted_revision(record.topic_key) == expected_base

      check_content!(record.title, record.content, evidence)
      normalized = normalize_sources!(sources)
      raise Error, :source_unverified unless normalized.present? && @source_verifier.current?(project: @project, sources: normalized)

      candidate = if record.validated_at?
        scoped.new(title: record.title, content: record.content, topic_key: record.topic_key,
                   terminal_session_id: record.terminal_session_id, revision: SecureRandom.uuid, base_revision: record.revision,
                   language: record.language, tags: record.tags)
      else
        record
      end
      # Engram also deduplicates content across topic keys; revisions must own separate index IDs.
      indexed_content = "[Flow memory revision: #{candidate.revision}]\n#{candidate.content}"
      engram_id = client.save(project: namespace, title: candidate.title, content: indexed_content,
                               topic_key: "#{candidate.topic_key}:#{candidate.revision}")
      raise Error, :unavailable if engram_id.blank?

      scoped.where(topic_key: record.topic_key, state: "validated").where.not(id: record.id).find_each do |previous|
        previous.update!(state: "obsolete")
      end
      candidate.update!(state: "validated", evidence: evidence, sources: normalized, validated_at: Time.current,
                        review_at: 30.days.from_now, engram_id: engram_id.to_s, validated_by_id: reviewer.id)
      record.update!(state: "obsolete") if candidate != record
      candidate
    end
  end

  def obsolete!(memory:, expected_revision:, reviewer:)
    operation(reviewer: reviewer, cleanup: true) do
      record = scoped.find_by(id: memory.id, revision: expected_revision)
      raise Error, :revision_conflict unless record

      record.update!(state: "obsolete")
      record
    end
  end

  def purge!(memory:, expected_revision:, reviewer:)
    operation(reviewer: reviewer, cleanup: true) do
      record = scoped.find_by(id: memory.id, revision: expected_revision)
      raise Error, :revision_conflict unless record

      record.destroy!
      { deleted: true, projection_cleanup: "queued" }
    end
  end

  private

  def operation(reviewer: nil, cleanup: false)
    @project = @session&.project || @review_project
    raise Error, :disabled unless @project

    failure = nil
    result = @project.with_lock do
      run = proc do
        if reviewer
          authorize_review!(reviewer, cleanup: cleanup)
        else
          raise Error, :disabled unless @session && @session.project_id == @project.id && self.class.serves?(@session)
        end

        begin
          yield
        rescue Engram::Client::Unavailable
          failure = Error.new(:unavailable)
          if @session&.persisted?
            counters["failures"] = counters.fetch("failures", 0) + 1
            save_counters!
          end
          nil
        rescue Error => error
          failure = error
          nil
        end
      end
      @session&.persisted? ? @session.with_lock { run.call } : run.call
    end
    raise failure if failure

    result
  rescue ActiveRecord::RecordInvalid
    raise Error, :invalid_capture
  end

  def authorize_review!(reviewer, cleanup: false)
    membership = reviewer.company_memberships.active.find_by(company_id: @project.company_id)
    permitted = membership && !membership.viewer? && (@project.owner_id == reviewer.id || membership.admin?)
    raise Error, :forbidden unless (cleanup || (Engram::Client.configured? && @project.memory_enabled?)) &&
      @project.accessible_by?(reviewer) && permitted && (@session.nil? || (@project.company_id == @session.company_id && @session.project_id == @project.id))
  end

  def client
    @client ||= Engram::Client.build
  end

  def namespace
    "flow:company:#{@project.company_id}:project:#{@project.id}"
  end

  def scoped
    ProjectMemory.where(project_id: @project.id)
  end

  def accepted_revision(topic_key)
    scoped.where(topic_key: topic_key).where.not(validated_at: nil).where.not(state: "obsolete")
          .order(created_at: :desc, id: :desc).pick(:revision)
  end

  def counters
    @session.metadata["project_memory"] ||= {}
  end

  def save_counters!
    @session.update!(metadata: @session.metadata)
  end

  def consume!(key, maximum)
    key = key.to_s
    raise Error, :budget_exhausted if counters.fetch(key, 0) >= maximum

    counters[key] = counters.fetch(key, 0) + 1
    save_counters!
  end

  def reserve_retrieval!
    @available_tokens = 2000 - counters.fetch("retrieved_tokens", 0)
    raise Error, :budget_exhausted if @available_tokens <= 0

    @response_tokens = 0
    consume!(:retrieval_calls, 5)
  end

  def settle_tokens!(results, kind)
    payload = kind == "detail" ? results.first : results
    actual = (payload.to_json.length / 4.0).ceil
    raise Error, :budget_exhausted if actual > @available_tokens

    results.each do |result|
      MemoryRetrieval.create!(project: @project, terminal_session: @session, project_memory_id: result[:id],
                              revision: result[:revision], title: result[:title], content: result[:content],
                              kind: kind, payload: result)
    end
    counters["retrieved_tokens"] = counters.fetch("retrieved_tokens", 0) + actual
    save_counters!
  end

  def snapshot(memory, content)
    result = { id: memory.id, revision: memory.revision, title: memory.title, content: content,
               sources: memory.sources, language: memory.language, topic_key: memory.topic_key, tags: memory.tags, validated_at: memory.validated_at.iso8601, review_at: memory.review_at.iso8601,
               reference_only: true }
    estimated_tokens = (result.to_json.length / 4.0).ceil
    @response_tokens = @response_tokens.to_i + estimated_tokens
    raise Error, :budget_exhausted if @response_tokens > @available_tokens

    result
  end

  def current?(memory)
    return true if @source_verifier.current?(project: @project, sources: memory.sources)

    memory.update!(state: "pending")
    false
  end

  def check_content!(*values)
    raise Error, :invalid_capture unless values.all? { |value| value.is_a?(String) && value.present? && value.length <= 2000 }

    sensitive = /\bBearer\s+[A-Za-z0-9._-]{12,}|-----BEGIN .*PRIVATE KEY-----|\b(?:gh[pousr]_|github_pat_|sk-(?:proj-)?)[A-Za-z0-9_-]{12,}|\bAKIA[A-Z0-9]{16}|(?:password|api[_-]?key|access[_-]?token|secret)["\']?\s*[:=]\s*["\']?\S+/i
    transcript = /(?:^|\n)(?:user|assistant|system):|"role"\s*:\s*"(?:user|assistant|system)"/i
    raise Error, :sensitive_content if values.any? { |value| sensitive.match?(value) || transcript.match?(value) }
  end

  def normalize_sources!(sources, attached: false)
    raise Error, :invalid_sources unless sources.is_a?(Array) && sources.length <= 3

    sources.map do |source|
      raise Error, :invalid_sources unless source.is_a?(Hash)

      value = source.stringify_keys.slice("repository_id", "path", "revision")
      path = value["path"]
      revision = value["revision"]
      raise Error, :invalid_sources unless path.is_a?(String) && path.present? && path.length <= 300 &&
        !path.start_with?("/") && !path.split("/").include?("..") && !path.match?(/[\x00-\x1f]/) &&
        revision.is_a?(String) && revision.match?(/\A[0-9a-f]{40,64}\z/)
      check_content!(path)
      repository = @project.repositories.find_by(id: value["repository_id"])
      raise Error, :invalid_sources unless repository && (!attached || @session.repositories.exists?(id: repository.id))

      value.merge("repository_id" => repository.id)
    end
  end
end
