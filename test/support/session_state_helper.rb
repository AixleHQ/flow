# frozen_string_literal: true

# TerminalSession's state machine refuses a direct write of `state` (AASM
# `no_direct_assignment`): a state changes only through an event fired by
# Sessions::Lifecycle. A test that needs a session already in some state, with no
# interest in how it got there, puts it there with this helper. It writes the attribute
# without the setter, so validations and callbacks of the save still run, and no event
# or effect of a transition does.
module SessionStateHelper
  def put_session_in_state!(session, state, **attributes)
    session.assign_attributes(attributes)
    session[:state] = state.to_s
    session.save!
    session
  end

  # An unsaved session in `state`, for the model's state predicates.
  def new_session_in_state(state)
    TerminalSession.new.tap { |session| session[:state] = state.to_s }
  end
end
