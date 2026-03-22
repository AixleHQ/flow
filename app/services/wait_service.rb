# frozen_string_literal: true

class WaitService
  class << self
    def resolve_github_checks(repo_full_name:, pr_number:, conclusion:)
      waits = TaskWait
        .pending
        .for_repository(repo_full_name)
        .where("metadata->>'repo_full_name' = ?", repo_full_name)
        .for_github_pr_number(pr_number)

      waits.find_each do |wait|
        TaskService.resolve_wait(
          wait: wait,
          resolution_data: { conclusion: conclusion }
        )
      end
    end
  end
end
