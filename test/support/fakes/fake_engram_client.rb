# frozen_string_literal: true

class FakeEngramClient
  attr_accessor :observations, :unavailable
  attr_reader :saved_observations, :searches, :deletions

  def initialize
    @observations = []
    @saved_observations = []
    @searches = []
    @deletions = []
    @sequence = 0
  end

  def search(project:, query:, limit:)
    check_available!
    @searches << { project: project, query: query, limit: limit }
    observations.select do |row|
      row["project"] == project && "#{row['title']} #{row['content']}".downcase.include?(query.downcase)
    end.first(limit).map(&:dup)
  end

  def save(project:, title:, content:, topic_key:)
    check_available!
    existing = saved_observations.find do |row|
      row[:project] == project && (row[:topic_key] == topic_key || (row[:title] == title && row[:content] == content))
    end
    id = existing ? existing[:id] : (@sequence += 1)
    @saved_observations << { id: id, project: project, title: title, content: content, topic_key: topic_key }
    @observations.reject! { |row| row["id"].to_s == id.to_s }
    @observations << { "id" => id, "project" => project, "title" => title, "content" => content }
    id
  end

  def delete(id:, project:)
    check_available!
    @deletions << { id: id, project: project }
    @observations.reject! { |row| row["id"].to_s == id.to_s && row["project"] == project }
    true
  end

  private

  def check_available!
    raise Engram::Client::Unavailable, "Project memory is unavailable" if unavailable
  end
end
