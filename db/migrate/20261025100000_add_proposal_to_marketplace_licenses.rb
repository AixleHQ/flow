# frozen_string_literal: true

class AddProposalToMarketplaceLicenses < ActiveRecord::Migration[8.1]
  # A subscription asking to be applied to a workspace that already exists.
  #
  # A buyer whose email domain already has a workspace cannot create a second
  # one, so until now they paid and the licence stayed bound to nothing. The
  # obvious fix -- attach it to the workspace at their domain -- is the one the
  # design says not to automate: it moves that workspace onto AWS billing
  # silently, and anyone holding an address at the domain could re-bill somebody
  # else's workspace through their own AWS account.
  #
  # So the buyer proposes and an administrator of that workspace decides. These
  # columns are the proposal. They sit on the licence rather than in a table of
  # their own because a licence has at most one live proposal and a second
  # replaces the first; a table would buy a history of declined ones, which
  # nothing needs until somebody disputes one.
  def change
    change_table :marketplace_licenses, bulk: true do |t|
      t.references :proposed_company, foreign_key: { to_table: :companies }, index: true
      # The address the buyer proved by opening a link sent to it, which is what
      # stops a proposal being raised against a domain the proposer has no
      # address at.
      t.string :proposed_by_email
      t.datetime :proposed_at
      t.datetime :proposal_decided_at
      t.string :proposal_state
    end
  end
end
