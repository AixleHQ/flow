# frozen_string_literal: true

module DataFlow
  # A workflow's "Run after" edges, as keys (step ids, or a builder draft's
  # `new-<n>` keys). Files and checks follow the whole chain: a session that runs
  # after Session 2, which runs after Session 1, is downstream of both.
  class Graph
    # @param edges [Hash{String => Array<String>}] key => the keys it runs after
    def initialize(edges)
      @edges = edges.to_h { |key, deps| [ key.to_s, Array(deps).map(&:to_s) ] }
    end

    def keys = @edges.keys

    # Every key `key` runs after, nearest first: direct dependencies, then theirs.
    # A key reachable along two paths sits at its shortest distance.
    def upstream(key)
      seen = { key.to_s => true }
      order = []
      frontier = [ key.to_s ]
      until frontier.empty?
        frontier = frontier.flat_map { |k| @edges.fetch(k, []) }.uniq.reject { |k| seen[k] }
        frontier.each { |k| seen[k] = true }
        order.concat(frontier)
      end
      order
    end

    def upstream?(key, of:) = upstream(of).include?(key.to_s)
  end
end
