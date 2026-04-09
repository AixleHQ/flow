# frozen_string_literal: true

class BoardPresets
  PRESETS = {
    simple_kanban: {
      display_name: "Simple Kanban",
      columns: [
        { name: "Backlog", position: 1, purpose: "Tasks waiting to be started." },
        { name: "In Progress", position: 2, purpose: "Tasks currently being worked on." },
        { name: "Done", position: 3, purpose: "Completed tasks." }
      ]
    },
    dev_team: {
      display_name: "Dev Team",
      columns: [
        { name: "Backlog", position: 1, purpose: "Tasks ready for development. Pick the highest priority item." },
        { name: "Tech Design", position: 2, purpose: "Technical design phase. Agent should analyze requirements, propose architecture, and produce a tech design document as a comment with tag 'tech_design'." },
        { name: "Implementation", position: 3, purpose: "Active development. Agent implements the solution based on tech design, writes code and tests." },
        { name: "Code Review", position: 4, purpose: "Code review phase. Agent reviews implementation for quality, correctness, and adherence to standards. Produces review as comment with tag 'code_review'." },
        { name: "QA", position: 5, purpose: "Quality assurance phase. Agent runs test suites, validates acceptance criteria, produces QA report as comment with tag 'qa_report'." },
        { name: "Ready for Release", position: 6, purpose: "Task approved and waiting to be included in the next release." },
        { name: "Done", position: 7, purpose: "Task completed and approved." }
      ]
    },
    full_sdlc: {
      display_name: "Full SDLC",
      columns: [
        { name: "Backlog", position: 1, purpose: "Tasks in queue, not yet prioritized for current iteration." },
        { name: "Ready for Design", position: 2, purpose: "Task is prioritized and waiting for product/UX design phase." },
        { name: "In Design", position: 3, purpose: "Product/UX design phase. Define user flows, wireframes, and requirements." },
        { name: "Design Review", position: 4, purpose: "Design review phase. Validate UX decisions and requirements." },
        { name: "Ready for Tech Design", position: 5, purpose: "Design approved, waiting for technical design to begin." },
        { name: "In Tech Design", position: 6, purpose: "Technical design phase. Agent analyzes requirements, proposes architecture, produces tech design as comment with tag 'tech_design'." },
        { name: "Tech Design Review", position: 7, purpose: "Tech design review phase. Validate architecture decisions and technical approach." },
        { name: "Ready for Dev", position: 8, purpose: "Tech design approved, task is ready to be picked up for implementation." },
        { name: "In Development", position: 9, purpose: "Active development. Agent implements the solution, writes code and tests based on tech design." },
        { name: "Code Review", position: 10, purpose: "Code review phase. Agent reviews implementation for quality and correctness. Produces review as comment with tag 'code_review'." },
        { name: "Ready for QA", position: 11, purpose: "Implementation reviewed and approved, waiting for QA." },
        { name: "In QA", position: 12, purpose: "Quality assurance phase. Agent runs test suites, validates acceptance criteria, produces QA report as comment with tag 'qa_report'." },
        { name: "QA Approved", position: 13, purpose: "QA passed, task is verified and ready for user acceptance testing." },
        { name: "Ready for UAT", position: 14, purpose: "Task waiting for user acceptance testing." },
        { name: "In UAT", position: 15, purpose: "User acceptance testing in progress. Stakeholders validate the feature." },
        { name: "UAT Approved", position: 16, purpose: "UAT passed, feature accepted by stakeholders." },
        { name: "Ready for Release", position: 17, purpose: "Task approved and waiting to be included in the next release." },
        { name: "In Release", position: 18, purpose: "Deployment in progress. Code being released to production." },
        { name: "Done", position: 19, purpose: "Task completed, released, and verified in production." }
      ]
    }
  }.freeze

  Entry = Struct.new(:key, :display_name, :columns, keyword_init: true)

  def self.all
    PRESETS.map do |key, data|
      Entry.new(key: key, display_name: data[:display_name], columns: data[:columns].map { |c| c[:name] })
    end
  end

  def self.find(key)
    PRESETS[key.to_sym]
  end

  def self.valid?(key)
    PRESETS.key?(key.to_sym)
  end
end
