# frozen_string_literal: true

require "test_helper"

class ActionMcpDynamicToolsTest < ActiveSupport::TestCase
  class StubToolsHandler
    include ActionMCP::Server::Tools

    attr_reader :error_calls, :response_calls

    def initialize
      @error_calls = []
      @response_calls = []
    end

    def send_jsonrpc_error(request_id, code, message, data = nil)
      @error_calls << {
        request_id: request_id,
        code: code,
        message: message,
        data: data
      }
    end

    def send_jsonrpc_response(request_id, result: nil, error: nil)
      @response_calls << {
        request_id: request_id,
        result: result,
        error: error
      }
    end
  end

  setup do
    ActionMCP::Current.terminal_session = nil
    Rails.logger.stubs(:error)
  end

  teardown do
    ActionMCP::Current.reset
  end

  test "tools list returns explicit internal error when terminal session context is missing" do
    handler = StubToolsHandler.new

    handler.send_tools_list("req-1")

    assert_empty handler.response_calls
    assert_equal 1, handler.error_calls.size
    assert_equal :internal_error, handler.error_calls.first[:code]
    assert_equal "Terminal session context is missing for this MCP request", handler.error_calls.first[:message]
  end

  test "tools call returns explicit internal error when terminal session context is missing" do
    handler = StubToolsHandler.new

    handler.send_tools_call("req-2", "board_get_task", {})

    assert_empty handler.response_calls
    assert_equal 1, handler.error_calls.size
    assert_equal :internal_error, handler.error_calls.first[:code]
    assert_equal "Terminal session context is missing for this MCP request", handler.error_calls.first[:message]
  end
end
