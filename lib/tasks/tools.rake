# frozen_string_literal: true

namespace :tools do
  desc "Run a tool by name through Temporal container workflow. " \
       "Usage: rake tools:run NAME=slack_history PARAMS='channel:projectx-eng,SLACK_RANGE:7d' " \
       "[COMPANY=dualboot] [PROJECT=aixle-mvp] [TIMEOUT=300] [SYNC=true]"
  task run: :environment do
    name       = ENV.fetch("NAME") { abort "NAME is required" }
    company_slug = ENV["COMPANY"] || "dualboot"
    project_slug = ENV["PROJECT"]
    timeout    = (ENV["TIMEOUT"] || 300).to_i
    sync       = ENV.fetch("SYNC", "true") == "true"
    params     = parse_params(ENV["PARAMS"])

    company = Company.find_by!(slug: company_slug)
    project = project_slug ? company.projects.find_by!(slug: project_slug) : nil

    tool = resolve_tool(name, company, project)
    puts "Tool: #{tool.display_name} (#{tool.kind}/#{tool.execution_mode})"
    puts "Params: #{params}" if params.any?

    if tool.execution_mode.app?
      run_app_tool(tool, params, project)
    else
      run_container_tool(tool, params, company, project, timeout, sync)
    end
  end

  def parse_params(raw)
    return {} if raw.blank?
    raw.split(",").each_with_object({}) do |pair, h|
      k, v = pair.split(":", 2)
      h[k.strip] = v&.strip
    end
  end

  def resolve_tool(name, company, project)
    Tool.find_by(name: name, kind: %w[system internal workflow]) ||
      (project && Tool.find_by(name: name, scope: project)) ||
      Tool.find_by(name: name, scope: company) ||
      abort("Tool '#{name}' not found")
  end

  def run_app_tool(tool, params, project)
    result = InternalToolExecutor.execute(tool, params, nil)
    puts "Exit: #{result[:exit_code]}"
    puts result[:stdout] if result[:stdout].present?
    $stderr.puts result[:stderr] if result[:stderr].present?
  end

  def run_container_tool(tool, params, company, project, timeout, sync)
    tool_result = ToolResult.create!(
      tool: tool,
      execution_id: ToolResult.generate_id,
      state: "processing"
    )
    puts "ToolResult: #{tool_result.execution_id}"

    wf_result = tool.execute(
      parameters: params,
      project: project,
      timeout: timeout,
      tool_result_id: tool_result.id
    )

    unless wf_result[:ok]
      abort "Workflow start failed: #{wf_result[:error]}"
    end

    puts "Workflow: #{wf_result[:workflow_id]}"

    if sync
      puts "Waiting for completion..."
      handle = wf_result[:handle]
      begin
        handle.result
      rescue Temporalio::Error::WorkflowFailedError => e
        puts "Workflow failed: #{e.message}"
      end
      tool_result.reload
      print_tool_result(tool_result)
    else
      puts "Async — check later: rake tools:result ID=#{tool_result.execution_id}"
    end
  end

  def print_tool_result(tr)
    puts "---"
    puts "State: #{tr.state}"
    puts "Exit code: #{tr.exit_code}"
    puts "Duration: #{tr.duration_ms}ms" if tr.duration_ms
    puts "Error: #{tr.error}" if tr.error.present?

    if tr.stdout
      puts "\n=== STDOUT ==="
      puts tr.stdout.read
    end
    if tr.stderr
      puts "\n=== STDERR ==="
      puts tr.stderr.read
    end
  end

  # -------------------------------------------------------
  desc "Check a tool result by execution ID. Usage: rake tools:result ID=tr-abc123..."
  task result: :environment do
    id = ENV.fetch("ID") { abort "ID is required" }
    tr = ToolResult.find_by!(execution_id: id)
    print_tool_result(tr)
  end
end
