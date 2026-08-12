# frozen_string_literal: true

# A standalone session as one row of the unified Sessions & Runs feed.
#
# Deliberately much leaner than TerminalSessionResource: the list needs a name,
# a status, who ran it and what it cost. Route tokens, IDE URLs and config blobs
# are detail-page concerns and serializing them per row was most of the payload.
class SessionListEntryResource < ApplicationResource
  typelize_from TerminalSession

  attributes :id, :state, :session_type, :agent_type, :mode,
             :total_tokens, :cost_cents,
             :started_at, :finished_at, :created_at

  typelize :string
  attribute :kind do |_session|
    "session"
  end

  # Sessions have no title column. The first line of the prompt is what the
  # person actually asked for, and it is what they recognise the row by; a
  # promptless interactive session falls back to the generic label the design
  # shows for exactly that case.
  typelize :string
  attribute :name do |session|
    SessionListEntryResource.display_name(session, viewable_for?(session))
  end

  typelize :string?
  attribute :user_name do |session|
    session.user&.name
  end

  # False when the owner's profile keeps this phase of their sessions private —
  # the row still reports what it cost, but it cannot be opened.
  typelize :boolean
  attribute :viewable do |session|
    viewable_for?(session)
  end

  MAX_NAME_LENGTH = 80

  def self.display_name(session, viewable = true)
    prompt = viewable ? session.initial_prompt : nil
    first_line = prompt.to_s.strip.lines.first.to_s.strip
    return "Interactive session" if first_line.blank?

    first_line.truncate(MAX_NAME_LENGTH)
  end

  private

  def viewable_for?(session)
    return true unless params.key?(:viewer)

    @viewable ||= {}
    key = session.id
    return @viewable[key] if @viewable.key?(key)

    @viewable[key] = session.visible_to?(params[:viewer])
  end
end
