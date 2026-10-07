# frozen_string_literal: true

require "test_helper"

class DataFlow::GraphTest < ActiveSupport::TestCase
  test "upstream follows the whole chain, nearest first, each key once" do
    graph = DataFlow::Graph.new("report" => %w[analyze], "analyze" => %w[collect fetch], "fetch" => %w[collect],
                                "collect" => [])

    assert_equal %w[analyze collect fetch], graph.upstream("report")
    assert graph.upstream?("collect", of: "report")
    refute graph.upstream?("report", of: "collect")
    assert_empty graph.upstream("collect")
  end

  test "a cycle does not loop" do
    graph = DataFlow::Graph.new("a" => %w[b], "b" => %w[a])

    assert_equal %w[b], graph.upstream("a")
  end
end
