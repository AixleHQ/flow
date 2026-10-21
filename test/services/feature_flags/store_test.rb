# frozen_string_literal: true

require "test_helper"

# The database-backed store, against real rows and the in-memory version token.
class FeatureFlags::StoreTest < ActiveSupport::TestCase
  REFRESH = 5
  STALENESS = 60

  setup do
    @now = 1_000.0
    @token = FakeFeatureFlagVersionToken.new
    @company = create(:company)
  end

  uses_feature_registry FeatureFlagsHelper::EXAMPLE_REGISTRY

  def build_store(loader: -> { FeatureFlag.load_snapshot })
    FeatureFlags::Store.new(version_token: @token, refresh_interval: REFRESH, max_staleness: STALENESS,
                            loader: loader, clock: -> { @now })
  end

  def advance(seconds) = @now += seconds

  def set_global(key, enabled)
    FeatureFlag.find_or_create_by!(key: key.to_s).update!(enabled: enabled)
  end

  def set_override(key, company, enabled)
    flag = FeatureFlag.find_or_create_by!(key: key.to_s)
    flag.overrides.create!(company: company, enabled: enabled, reason: "pilot")
  end

  # Feature.enabled? against this store, as a request would see it.
  def with_store(store)
    previous = FeatureFlags.store
    FeatureFlags.store = store
    Current.feature_snapshot = nil
    yield
  ensure
    FeatureFlags.store = previous
    Current.feature_snapshot = nil
  end

  test "the snapshot holds every row: global values and per-company overrides" do
    set_global(:coder_reap, false)
    set_override(:board_ai_summary, @company, true)

    snapshot = build_store.snapshot

    assert_equal({ coder_reap: { global: false, overrides: {} },
                   board_ai_summary: { global: nil, overrides: { @company.id => true } } }, snapshot.to_h)
    assert_predicate snapshot, :frozen?
  end

  test "a fresh install has no rows, and every flag resolves to its declared default" do
    store = build_store

    assert_empty store.snapshot.to_h
    with_store(store) do
      assert_equal :default, Feature.explain(:coder_reap).source
      assert_equal :default, Feature.explain(:board_ai_summary, company: @company).source
    end
  end

  test "a flag check performs no database query and no Redis call" do
    set_override(:board_ai_summary, @company, true)
    store = build_store
    store.snapshot
    reads = @token.reads

    with_store(store) do
      assert_no_queries do
        20.times do
          Current.feature_snapshot = nil
          assert Feature.enabled?(:board_ai_summary, company: @company)
          assert Feature.enabled?(:coder_reap)
        end
      end
    end
    assert_equal reads, @token.reads
  end

  test "the version token is read at most once per refresh interval" do
    store = build_store

    10.times { store.snapshot }
    assert_equal 1, @token.reads

    advance(REFRESH - 1)
    10.times { store.snapshot }
    assert_equal 1, @token.reads

    advance(1)
    10.times { store.snapshot }
    assert_equal 2, @token.reads

    advance(REFRESH * 3)
    10.times { store.snapshot }
    assert_equal 3, @token.reads
  end

  test "an unchanged token reloads nothing until max staleness" do
    store = build_store
    store.snapshot
    advance(REFRESH)

    assert_no_queries { store.snapshot }
  end

  test "a write and a bump reach another store after the refresh interval" do
    reader = build_store
    assert_nil reader.snapshot.global(:coder_reap)

    set_global(:coder_reap, false)
    @token.bump

    advance(REFRESH - 1)
    assert_nil reader.snapshot.global(:coder_reap), "nothing is checked before the interval ends"

    advance(1)
    assert_equal false, reader.snapshot.global(:coder_reap) # rubocop:disable Minitest/RefuteFalse
  end

  test "with the version token unavailable a write is picked up after max staleness" do
    reader = build_store
    reader.snapshot
    @token.unavailable = true

    set_override(:board_ai_summary, @company, true)
    @token.bump

    advance(STALENESS - 1)
    assert_nil reader.snapshot.override(:board_ai_summary, @company.id)

    advance(1)
    assert reader.snapshot.override(:board_ai_summary, @company.id)
  end

  test "a failed reload keeps serving the last good values, reports, and retries at the next interval" do
    set_global(:coder_reap, false)
    database_down = false
    store = build_store(loader: lambda {
      raise ActiveRecord::ConnectionNotEstablished, "connection refused" if database_down

      FeatureFlag.load_snapshot
    })
    store.snapshot

    set_global(:coder_reap, true)
    @token.bump
    database_down = true
    advance(REFRESH)

    report = capture_error_reports(ActiveRecord::ConnectionNotEstablished) { store.snapshot }.sole
    assert_equal [ FeatureFlags::RELOAD_FAILED_SOURCE, true ], [ report.source, report.context[:loaded] ]
    assert_equal false, store.snapshot.global(:coder_reap) # rubocop:disable Minitest/RefuteFalse
    with_store(store) { assert_equal [ false, :global ], [ Feature.enabled?(:coder_reap), Feature.explain(:coder_reap).source ] }

    database_down = false
    advance(REFRESH)
    assert store.snapshot.global(:coder_reap)
  end

  test "with the database unreachable on first load, flags resolve from ENV and their declared defaults" do
    set_global(:coder_reap, false)
    database_down = true
    store = build_store(loader: lambda {
      raise ActiveRecord::ConnectionNotEstablished, "connection refused" if database_down

      FeatureFlag.load_snapshot
    })

    report = capture_error_reports(ActiveRecord::ConnectionNotEstablished) { store.snapshot }.sole
    assert_equal false, report.context[:loaded] # rubocop:disable Minitest/RefuteFalse
    assert_same FeatureFlags::Snapshot::EMPTY, store.snapshot

    with_store(store) do
      assert_equal [ true, :default ], [ Feature.enabled?(:coder_reap), Feature.explain(:coder_reap).source ]
      stub_feature_env(:coder_reap, "off") do
        assert_equal [ false, :env ], [ Feature.enabled?(:coder_reap), Feature.explain(:coder_reap).source ]
      end
    end

    database_down = false
    advance(REFRESH)
    assert_equal false, store.snapshot.global(:coder_reap) # rubocop:disable Minitest/RefuteFalse
  end

  test "a check that arrives during the first load waits for it instead of answering from the defaults" do
    set_global(:coder_reap, false)
    set_override(:board_ai_summary, @company, true)
    # Built here, so the loader thread needs no database connection of its own.
    loaded = FeatureFlag.load_snapshot
    load_started = Queue.new
    release_load = Queue.new
    loads = 0
    store = build_store(loader: lambda {
      loads += 1
      load_started << true
      release_load.pop
      loaded
    })

    first = Thread.new { store.snapshot }
    load_started.pop
    second_entering = Queue.new
    second = Thread.new do
      second_entering << true
      store.snapshot
    end
    second_entering.pop
    # Without waiting on the lock the second check would return within this
    # window, with the defaults; it must still be waiting for the first load.
    assert_nil second.join(0.5), "the second check waits for the first load"
    release_load << true

    [ first, second ].each { |thread| thread.join(5) }
    assert_same loaded, first.value
    assert_same loaded, second.value, "the second check must see the loaded values, not Snapshot::EMPTY"
    assert_equal 1, loads, "the waiting check does not load a second time"
    assert_equal 1, @token.reads
  end

  test "once a snapshot is loaded, a check that finds a refresh running serves it without waiting" do
    store_snapshot = nil
    loads = 0
    load_started = Queue.new
    release_load = Queue.new
    store = build_store(loader: lambda {
      loads += 1
      if loads > 1
        load_started << true
        release_load.pop
      end
      store_snapshot = FeatureFlags::Snapshot.new({ coder_reap: { global: loads.odd?, overrides: {} } })
    })
    first_snapshot = store.snapshot

    @token.bump
    advance(REFRESH)
    refreshing = Thread.new { store.snapshot }
    load_started.pop

    assert_same first_snapshot, store.snapshot, "served the held snapshot while the refresh runs"
    release_load << true
    refreshing.join(5)
    assert_same store_snapshot, store.snapshot
    refute_same first_snapshot, store_snapshot
  end

  test "a value changed mid-request does not change the answer inside that request" do
    store = build_store

    with_store(store) do
      Rails.application.executor.wrap do
        assert Feature.enabled?(:coder_reap)

        set_global(:coder_reap, false)
        @token.bump
        advance(REFRESH)

        assert Feature.enabled?(:coder_reap), "the request keeps the snapshot its first check pinned"
        assert_equal false, store.snapshot.global(:coder_reap) # rubocop:disable Minitest/RefuteFalse

        Current.reset
        refute Feature.enabled?(:coder_reap), "the next request sees the new value"
      end
    end
  end
end
