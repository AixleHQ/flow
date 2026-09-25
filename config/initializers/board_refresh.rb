# frozen_string_literal: true

Rails.application.executor.to_complete { BoardRefresh.flush! }
