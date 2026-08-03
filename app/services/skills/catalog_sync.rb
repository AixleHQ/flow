# frozen_string_literal: true

module Skills
  # Refreshes the local skills catalog from skills.sh.
  #
  # WHY THIS IS A SWEEP AND NOT A WALK
  # MCP::ConnectorCatalogSync resumes from a watermark because the MCP registry
  # publishes a cursor and an `updated_since` filter. skills.sh publishes neither,
  # and has no list endpoint on any reachable surface — the only place install
  # counts appear is the search response. So coverage is built by fanning out over
  # seed queries drawn from the registry's own published taxonomy, and freshness is
  # "re-derive periodically" rather than "continue from where we stopped".
  #
  # CONSEQUENCE, STATED PLAINLY: this mirror is incomplete by construction. Its
  # coverage is a function of the seeds below, which is why typed searches still go
  # upstream live and only the default view is served from here.
  #
  # Idempotent and cadence-independent, like the connector sync: every row is
  # upserted on its natural key, ranking is recomputed wholesale rather than
  # incremented, and a missed week costs freshness rather than correctness. That
  # property is deliberate — this codebase has already lost dynamic schedules to a
  # worker redeploy once.
  class CatalogSync
    # Seeds from skills.sh's own taxonomy (`/topic/<slug>`, `/package/<ecosystem>`)
    # plus the domains its leaderboard is thickest in. Each returns up to 200 rows
    # for roughly 31 KB, so the whole sweep is a few MB.
    SEED_QUERIES = %w[
      react nextjs vue svelte angular typescript javascript python ruby rails go rust java php
      design ui ux frontend backend fullstack mobile ios android flutter
      testing playwright vitest jest cypress tdd debugging refactoring review
      database postgres mysql sqlite redis prisma supabase firebase
      api rest graphql grpc webhooks auth oauth security secrets
      docker kubernetes terraform aws azure gcp vercel cloudflare deploy ci
      agent agents mcp llm prompt rag embeddings
      docs writing markdown pdf excel powerpoint slides
      git github gitlab jira linear slack notion
      seo marketing analytics accessibility performance monitoring observability
      data etl pandas notebook ml pytorch
      shell cli automation scraping browser
    ].freeze

    # Owner-scoped sweeps for publishers whose skills matter more than a keyword
    # match would surface. The `owner` filter works on the public endpoint even
    # though it is documented only for `/api/v1`.
    SEED_OWNERS = %w[
      anthropics vercel-labs microsoft obra supabase firebase shadcn mattpocock
      currents-dev trailofbits ast-grep emilkowalski
    ].freeze

    PAGE_LIMIT = 200
    # Courtesy pacing. The public endpoints are rate-limited per IP with no
    # published number, and the terms warn specifically about "scraping that
    # bypasses the rate limit" while encouraging caching. This sweep is ~200
    # sequential requests once a week.
    REQUEST_DELAY = 0.15
    # Metadata backfill: the search response carries no description at all, and a
    # description is what tells an agent when to use a skill — so an undescribed row
    # is a card nobody can judge.
    #
    # How many undescribed rows a run considers. Generous, because most are answered
    # from GitHub raw, which costs nothing from any budget we care about.
    BACKFILL_LIMIT = 150
    # How many of those may fall through to the registry's download endpoint, which is
    # capped at a MEASURED 60 requests per hour for the whole deployment
    # (`RegistryClient::DOWNLOAD_HOURLY_LIMIT`) — a budget every user install also
    # spends. A bulk pass that ate it would make installing a skill fail while the
    # catalog prettied itself up, so a run takes a quarter and leaves the rest to
    # people. Enforced by counting, not by waiting for the 429.
    DOWNLOAD_BUDGET = 15
    # Audits are batched per repository, so the cost is one request per source
    # rather than per skill. Bounded because the catalog is much larger than the
    # part of it anyone browses.
    AUDIT_ROW_LIMIT = 300
    AUDIT_SOURCE_LIMIT = 40
    # One repository can hold hundreds of skills, and every slug goes into a single
    # query string. Sliced so a collection publisher cannot produce a URL long enough
    # to be refused (414) — which would leave the largest publishers unaudited.
    AUDIT_BATCH_SIZE = 40
    # Wall-clock budget for the whole run, comfortably inside the activity's
    # start_to_close of 1800s. nil disables it (tests).
    TIME_BUDGET = 20.minutes

    Result = Struct.new(:fetched, :upserted, :failed, :backfilled, :audited, keyword_init: true) do
      def to_s
        "fetched=#{fetched} upserted=#{upserted} failed=#{failed} " \
          "backfilled=#{backfilled} audited=#{audited}"
      end
    end

    def self.call(...) = new(...).call

    # Follows what people actually searched for instead of the static seed list. The
    # terms come from CatalogSearchQuery (unattributed, normalised), so a daily run
    # mirrors the slice of the registry users are about to install from — the part the
    # guessed-at topic seeds cannot know about. Owner sweeps are skipped: they are
    # broad coverage, which is the weekly run's job.
    def self.demand(client: RegistryClient, github: GithubSkillMd, delay: REQUEST_DELAY, budget: TIME_BUDGET)
      terms = CatalogSearchQuery.top_terms
      new(client: client, github: github, delay: delay, budget: budget, queries: terms, owners: []).call.tap do
        CatalogSearchQuery.prune!
      end
    end

    # `client` is injected rather than referenced directly so tests drive the sweep
    # through FakeSkillsRegistry instead of stubbing HTTP or the collaborator class.
    def initialize(client: RegistryClient, github: GithubSkillMd, delay: REQUEST_DELAY,
                   budget: TIME_BUDGET, queries: SEED_QUERIES, owners: SEED_OWNERS,
                   download_budget: DOWNLOAD_BUDGET)
      @client = client
      @github = github
      @delay = delay
      @download_budget = download_budget
      @queries = queries
      @owners = owners
      @deadline = budget && Time.current + budget
      @result = Result.new(fetched: 0, upserted: 0, failed: 0, backfilled: 0, audited: 0)
    end

    def call
      Rails.logger.info("[Skills::CatalogSync] Starting " \
                        "(#{@queries.size} queries, #{@owners.size} owners)")

      @queries.each { |query| sweep(query) }
      @owners.each { |owner| sweep(owner, owner: owner) }

      seed_featured
      refresh_ranking
      backfill_metadata
      refresh_audits

      Rails.logger.info("[Skills::CatalogSync] Finished #{@result}")
      @result
    end

    private

    # Every stage checks this. Each of ~100 searches can burn an open timeout plus a
    # read timeout against an unresponsive host, which on its own could outlast the
    # activity's start_to_close and leave the backfill and audits permanently
    # unreached. Running out of budget degrades coverage; it does not fail the run.
    def budget_left?
      return true if @deadline.nil?
      return true if Time.current < @deadline

      unless @budget_exhausted
        @budget_exhausted = true
        Rails.logger.warn("[Skills::CatalogSync] Time budget exhausted; skipping remaining work")
      end
      false
    end

    def sweep(query, owner: nil)
      return unless budget_left?

      entries = @client.search(query, limit: PAGE_LIMIT, owner: owner)
      @result.fetched += entries.size
      upsert(entries)
      sleep(@delay) if @delay.positive?
    end

    def upsert(entries)
      @result.upserted += CatalogUpsert.call(entries).size
    rescue ActiveRecord::ActiveRecordError => e
      # One bad batch must not abandon the sweep. Retry row by row rather than
      # discarding the page: a single entry violating a column constraint would
      # otherwise cost the other 199 rows on every run, forever.
      Rails.logger.error("[Skills::CatalogSync] Batch upsert failed (#{e.message}); retrying per row")
      retry_individually(entries)
    end

    def retry_individually(entries)
      entries.each do |entry|
        @result.upserted += CatalogUpsert.call([ entry ]).size
      rescue ActiveRecord::ActiveRecordError => e
        @result.failed += 1
        Rails.logger.error("[Skills::CatalogSync] Row upsert failed for #{entry.id.inspect}: #{e.message}")
      end
    end

    # Guarantees the curated seed exists even when no sweep query happened to reach
    # it, so the default view is never empty on a cold catalog. Seeds that turn out
    # not to be installable are removed again by #backfill_metadata.
    def seed_featured
      now = Time.current
      rows = CatalogSkill::FEATURED.filter_map do |registry_id|
        parts = registry_id.split("/").reject(&:blank?)
        # Loudly, not silently: a typo in the curated list would otherwise just make
        # a pick quietly absent from every project's default view.
        if parts.size < 2
          Rails.logger.error("[Skills::CatalogSync] Unusable FEATURED id #{registry_id.inspect}")
          next
        end

        {
          registry_id: registry_id,
          source: parts[0..-2].join("/"),
          slug: parts.last,
          installs: 0,
          created_at: now,
          updated_at: now
        }
      end
      return if rows.empty?

      # Nothing is updated on conflict: a swept row already carries a real install
      # count and title, and this pass must not overwrite them with zeroes.
      CatalogSkill.insert_all(rows, unique_by: :registry_id, record_timestamps: false)
    end

    # Signals skills.sh cannot supply, recomputed wholesale rather than incremented.
    # Two statements over a small table beat a counter that drifts.
    def refresh_ranking
      CatalogSkill.where(featured: true).where.not(registry_id: CatalogSkill::FEATURED)
                  .update_all(featured: false)
      CatalogSkill.where(registry_id: CatalogSkill::FEATURED).update_all(featured: true)

      refresh_install_counts
      refresh_bulk_publishers
    end

    # Our own demand signal. Skill#package is "source@slug" while a catalog row is
    # keyed "source/slug", so the two are matched by rewriting the separator.
    def refresh_install_counts
      counts = ::Skill.where(origin: "registry").where.not(package: nil).group(:package).count
                      .transform_keys { |package| package.to_s.sub("@", "/") }

      CatalogSkill.where.not(install_count: 0).where.not(registry_id: counts.keys).update_all(install_count: 0)
      counts.each { |registry_id, count| CatalogSkill.where(registry_id: registry_id).update_all(install_count: count) }
    end

    # Marks sources shipping a collection rather than a product, computed from the
    # mirror itself so it needs no maintained list and adapts as the catalog grows.
    def refresh_bulk_publishers
      CatalogSkill.connection.execute(<<~SQL.squish)
        UPDATE catalog_skills SET bulk_publisher = sub.bulk
        FROM (
          SELECT registry_id,
                 (COUNT(*) OVER (PARTITION BY source) >= #{CatalogSkill::BULK_PUBLISHER_THRESHOLD}) AS bulk
          FROM catalog_skills
        ) AS sub
        WHERE catalog_skills.registry_id = sub.registry_id
          AND catalog_skills.bulk_publisher IS DISTINCT FROM sub.bulk
      SQL
    end

    # Third-party security verdicts for the part of the catalog people actually see.
    #
    # This is the only external judgement available: a skills.sh id is a GitHub
    # coordinate with no ownership proof, so nothing here can be "vendor verified"
    # the way an MCP connector can. Batched per repository, which is how the skills
    # CLI itself asks.
    def refresh_audits
      candidates = CatalogSkill.order(featured: :desc, installs: :desc).limit(AUDIT_ROW_LIMIT).to_a

      # `catch`/`throw` so a throttle abandons the whole pass, not just the batch
      # inside one repository — the next repository would hit the same limit.
      catch(:audits_rate_limited) do
        candidates.group_by(&:source).first(AUDIT_SOURCE_LIMIT).each do |source, rows|
          break unless budget_left?

          audit_source(source, rows)
        end
      end
    end

    def audit_source(source, rows)
      rows.each_slice(AUDIT_BATCH_SIZE) do |batch|
        begin
          data = @client.audits(source, batch.map(&:slug))
        rescue RegistryClient::RateLimited => e
          Rails.logger.warn("[Skills::CatalogSync] Audits stopped — #{e.message}")
          throw :audits_rate_limited
        end

        sleep(@delay) if @delay.positive?
        # Unreachable or unparseable: leave existing verdicts alone rather than
        # blanking them because a lookup failed.
        next if data.blank?

        batch.each { |row| apply_audit(row, data) }
      end
    end

    def apply_audit(row, data)
      entry = data[row.slug]

      if entry.blank?
        # The endpoint answered for this repository but not for this skill: a
        # verdict was withdrawn or the skill is gone. A stale "risk: critical"
        # badge shown forever would be worse than no badge.
        return if row.audit.blank? && row.audit_risk.blank?

        row.update_columns(audit: {}, audit_risk: nil, audited_at: nil, updated_at: Time.current)
        return
      end

      row.update_columns(
        audit: entry,
        # Derived here so the column can never disagree with the payload.
        audit_risk: CatalogSkill.worst_risk(entry),
        audited_at: Time.current,
        updated_at: Time.current
      )
      @result.audited += 1
    end

    # Fills in what the search endpoint does not carry: a description, which is what
    # tells an agent when to use a skill.
    #
    # Rotation matters here. Selecting `where(description: nil)` ordered by `featured`
    # alone would re-fetch the same rows every week forever, because a SKILL.md
    # without a `description` key legitimately yields nil — those rows would hold the
    # whole budget and no other row would ever be reached. Ordering by
    # `registry_synced_at` and stamping it on every ATTEMPT (not just successes) makes
    # the queue rotate.
    def backfill_metadata
      # Ordered by the SAME ranking the grid uses, so the rows a user can actually
      # see are described first — `featured DESC` alone left most of the visible page
      # blank while spending the budget on entries nobody was looking at.
      # `updated_at` breaks ties, and since every attempt stamps it, rows that will
      # never yield a description rotate to the back instead of holding the budget.
      rows = CatalogSkill.where(description: nil)
                         .order(Arel.sql("#{CatalogSkill::RANKING}, updated_at ASC"))
                         .limit(BACKFILL_LIMIT)
      downloads_used = 0

      rows.each do |row|
        break unless budget_left?

        # GitHub raw first, because it costs nothing from the 60-per-hour download
        # budget that user installs also draw on. Only rows whose layout raw does not
        # cover fall through to the registry.
        content = @github.fetch(row.source, row.slug)
        bundle = nil

        if content.blank?
          # Stop DOWNLOADING, not scanning: the budget (and a 429) only applies to the
          # registry endpoint, while raw keeps answering for free. Aborting the whole
          # pass on the first refused download meant one early miss cost every row
          # behind it — which is exactly what happened on the first live run.
          if downloads_used < @download_budget && !@downloads_exhausted
            downloads_used += 1
            begin
              bundle = @client.download(row.source, row.slug)
              content = bundle&.skill_md
            rescue RegistryClient::RateLimited => e
              Rails.logger.warn("[Skills::CatalogSync] Download budget closed — #{e.message}")
              @downloads_exhausted = true
            end
          end
        end

        sleep(@delay) if @delay.positive?

        if content.blank?
          # A row we never actually asked about (budget closed) must not be judged:
          # marking it attempted would rotate it back for nothing, and dropping it
          # would delete a real entry because WE ran out of requests.
          drop_unresolvable_seed(row) unless @downloads_exhausted && bundle.nil?
          next
        end

        description = SkillMarkdown.description(content)
        row.update_columns(
          description: description,
          title: row.title.presence || SkillMarkdown.name(content),
          # Only the registry's own bundle carries a hash; a raw read has none, and
          # inventing one would break "has upstream changed since we looked".
          content_hash: bundle&.content_hash || row.content_hash,
          registry_synced_at: Time.current,
          updated_at: Time.current
        )
        # Counted only when a description actually landed, so the activity's summary
        # cannot report progress for a no-op.
        @result.backfilled += 1 if description.present?
      end
    end

    # A curated seed the registry cannot resolve is not a catalog entry — it is a card
    # that fails on click, at the top of every project's default view. But a failed
    # download is NOT evidence that a row is a phantom: rate limiting, a timeout, or
    # an entry the blob API simply has not built will all return nil.
    #
    # So the discriminator is provenance, not recency: `seed_featured` inserts without
    # `registry_synced_at`, while `CatalogUpsert` always sets it. A NULL there means
    # no sweep has EVER seen this row upstream — it exists only because the curated
    # list named it. Anything upstream has confirmed is kept and just has its attempt
    # stamped so the backfill queue rotates.
    #
    # An earlier version compared `registry_synced_at` against this run's start, which
    # deleted any row the current run's seeds happened not to match — 398 rows on the
    # first real backfill, and it would erase most of the catalog under a
    # demand-seeded daily sweep.
    def drop_unresolvable_seed(row)
      if row.registry_synced_at.nil?
        Rails.logger.warn("[Skills::CatalogSync] Dropping never-confirmed seed #{row.registry_id}")
        row.destroy
        return
      end

      # `updated_at`, not `registry_synced_at`: the latter means "upstream confirmed
      # this row", and a failed download confirms nothing.
      row.update_columns(updated_at: Time.current)
    end
  end
end
