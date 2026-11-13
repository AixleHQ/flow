# frozen_string_literal: true

module ProjectTeams
  # Resolves a team to the one member a run will belong to
  # (docs/design/project-teams.md, "Picking a member").
  #
  # A member qualifies when they can own runs in the project and hold a usable
  # credential for every runtime the run will need: each step's pinned runtime,
  # plus — when some step pins none — the runtime SessionService would fall back
  # to for them (the run's, else their own default, else their newest
  # credential). A credential whose login has expired, or whose quota is
  # exhausted, does not count.
  class Picker
    Skip = Data.define(:user, :reason, :held_until, :signed_out) do
      def initialize(user:, reason:, held_until: nil, signed_out: false) = super
    end

    Result = Data.define(:team, :user, :skipped) do
      def picked? = !user.nil?

      def message
        reasons = skipped.map { |skip| "#{skip.user.name}: #{skip.reason}" }
        reasons = [ "it has no members" ] if reasons.empty?
        "No member of team \"#{team.name}\" can take this run — #{reasons.join('; ')}."
      end
    end

    Candidate = Data.define(:user, :credentials)

    Preview = Data.define(:next_user, :skipped)

    # A launch reads usage readings from the cache and may ask a vendor for at
    # most this many missing ones: the vendors answer 429 to anything chattier.
    UNCACHED_READINGS = 1

    def self.call(...) = new(...).call

    # Who the next run would go to and why the others would be passed over, for a
    # run that pins no runtime: what the Teams page shows. Nothing is locked or
    # moved, and no vendor is asked.
    def self.preview(team, usage: Agents::SubscriptionUsageService.new)
      new(team: team, workflow: nil, usage: usage, uncached_readings: 0).preview
    end

    # @param exclude_user_ids [Array<Integer>] members this pick must pass over
    #   (the member a quota retry is moving away from)
    # @param usage [Agents::SubscriptionUsageService] the most_remaining reading source
    def initialize(team:, workflow:, agent_runtime: nil, exclude_user_ids: [],
                   usage: Agents::SubscriptionUsageService.new, uncached_readings: UNCACHED_READINGS)
      @team = team
      @workflow = workflow
      @agent_runtime = agent_runtime.presence
      @exclude_user_ids = Array(exclude_user_ids).compact
      @usage = usage
      @uncached_readings = uncached_readings
    end

    def call
      @team.with_lock do
        candidates, skipped = evaluate
        picked = choose(candidates)
        @team.update_columns(last_picked_user_id: picked.id) if picked && !@team.priority?
        Result.new(team: @team, user: picked, skipped: skipped)
      end
    end

    def preview
      candidates, skipped = evaluate
      Preview.new(next_user: choose(candidates), skipped: skipped)
    end

    private

    def project = @team.project

    def evaluate
      memberships = memberships_with_users
      user_ids = memberships.map(&:user_id)
      company_memberships = CompanyMembership.active.where(company_id: project.company_id, user_id: user_ids)
                                             .index_by(&:user_id)
      credentials = AgentCredential.where(company_id: project.company_id, user_id: user_ids)
                                   .order(created_at: :desc, id: :desc).group_by(&:user_id)

      candidates = []
      skipped = []
      memberships.each do |member|
        user = member.user
        verdict = assess(user, company_memberships[user.id], credentials.fetch(user.id, []))
        if verdict.is_a?(Skip)
          skipped << verdict
        else
          candidates << Candidate.new(user: user, credentials: verdict)
        end
      end
      [ candidates, skipped ]
    end

    # A Skip when the member cannot take the run; the credentials it needs otherwise.
    def assess(user, membership, credentials)
      skip = ->(reason, **details) { Skip.new(user: user, reason: reason, **details) }
      return skip.call("was passed over for this run") if @exclude_user_ids.include?(user.id)
      return skip.call("is no longer an active member of the company") if membership.nil?
      return skip.call("is a viewer, and viewers can't start runs") if membership.viewer?
      return skip.call("no longer has access to the project") unless project.accessible_by?(user)
      return skip.call("has no agent connected in this company") if credentials.empty?

      by_type = credentials.index_by(&:agent_type)
      runtimes = needed_runtimes(membership, credentials)
      missing = runtimes.reject { |runtime| by_type.key?(runtime) }
      return skip.call("has no #{labels(missing)} connected") if missing.any?

      needed = runtimes.map { |runtime| by_type.fetch(runtime) }
      signed_out = needed.select { |credential| signed_out?(credential) }
      return skip.call(signed_out_reason(signed_out), signed_out: true) if signed_out.any?

      exhausted = needed.select(&:quota_exhausted?)
      if exhausted.any?
        return skip.call(exhausted_reason(exhausted), held_until: exhausted.map(&:quota_exhausted_until).min)
      end

      needed
    end

    # The test SessionService's launch preflight applies: a run handed to a member
    # whose login it would refuse dies at launch instead of going to someone else.
    def signed_out?(credential)
      !credential.active? || credential.unrecoverably_expired?
    end

    def needed_runtimes(membership, credentials)
      pinned = steps.map(&:required_agent_runtime).compact_blank
      fallback = @agent_runtime || membership.default_agent_runtime.presence || credentials.first.agent_type
      unpinned = steps.empty? || steps.any? { |step| step.required_agent_runtime.blank? }
      (pinned + (unpinned ? [ fallback ] : [])).uniq
    end

    def steps
      @steps ||= @workflow ? @workflow.steps.not_deleted.to_a : []
    end

    def memberships_with_users
      @memberships ||= if @team.association(:memberships).loaded?
        @team.memberships.to_a
      else
        @team.memberships.includes(:user).to_a
      end
    end

    def labels(runtimes) = runtimes.map { |runtime| AgentRuntime.label_for(runtime) }.to_sentence

    def signed_out_reason(credentials)
      "#{labels(credentials.map(&:agent_type))} login expired — sign in again in Profile settings"
    end

    def exhausted_reason(credentials)
      credentials.map do |credential|
        "#{AgentRuntime.label_for(credential.agent_type)} quota exhausted until " \
          "#{credential.quota_exhausted_until.utc.strftime('%Y-%m-%d %H:%M UTC')}"
      end.join(", ")
    end

    # The strategy orders the candidates; the first of them not already running a
    # session on a runtime this run needs takes it, so parallel runs spread over
    # accounts instead of stacking on one. When every candidate is busy, the
    # strategy's first choice still takes it.
    def choose(candidates)
      return nil if candidates.empty?

      ordered = if @team.priority? then candidates
      elsif @team.round_robin? then rotate(candidates)
      else by_remaining(rotate(candidates))
      end
      busy = busy_pairs(ordered)
      (ordered.find { |candidate| candidate.credentials.none? { |c| busy.include?([ candidate.user.id, c.agent_type ]) } } ||
        ordered.first).user
    end

    def busy_pairs(candidates)
      TerminalSession.active.where(company_id: project.company_id, user_id: candidates.map { |c| c.user.id },
                                   agent_type: candidates.flat_map { |c| c.credentials.map(&:agent_type) }.uniq)
                     .distinct.pluck(:user_id, :agent_type).to_set
    end

    # Candidates in team order, starting after the member picked last.
    def rotate(candidates)
      order = memberships_with_users.map(&:user_id)
      cursor = order.index(@team.last_picked_user_id)
      return candidates if cursor.nil?

      candidates.sort_by { |candidate| (order.index(candidate.user.id) - cursor - 1) % order.size }
    end

    # Most quota left on the tightest window first; candidates with no reading
    # after, in round-robin order.
    def by_remaining(rotated)
      @fetches_left = @uncached_readings
      scored = rotated.each_with_index.map { |candidate, index| [ candidate, remaining(candidate), index ] }
      known, unknown = scored.partition { |_, score, _| score }
      known.sort_by { |_, score, index| [ -score, index ] }.map(&:first) + unknown.map(&:first)
    end

    def remaining(candidate)
      scores = candidate.credentials.map { |credential| remaining_share(credential) }
      scores.all? ? scores.min : nil
    end

    def remaining_share(credential)
      entry = @usage.usage_for(credential, fetch: false)
      if entry.nil? && @fetches_left.positive?
        @fetches_left -= 1
        entry = @usage.usage_for(credential, fetch: true)
      end
      windows = Array(entry&.dig(:windows))
      return nil unless entry&.dig(:status) == "ok" && windows.any?

      100.0 - windows.map { |window| window[:utilization].to_f }.max
    end
  end
end
