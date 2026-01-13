Octokit.configure do |c|
  c.auto_paginate = true
  c.per_page = Settings.integrations.github.per_page
end
