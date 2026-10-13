# frozen_string_literal: true

# One request to the AI provider, whatever came of it (the ledger Settings › AI
# shows and the month's token limit is checked against).
class Ai::Request < ApplicationRecord
  belongs_to :user, optional: true

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }

  def tokens = input_tokens + output_tokens
end
