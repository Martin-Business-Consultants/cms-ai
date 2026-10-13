# frozen_string_literal: true

# Every request to the AI provider, whatever came of it: who asked (a plugin's
# purpose, a person), which model through which endpoint, the tokens it took,
# and how it ended. The month's token limit is checked against these.
class CreateAiRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_requests do |t|
      t.string :purpose, null: false
      t.references :user
      t.string :provider, null: false
      t.string :model, null: false
      t.string :endpoint
      t.boolean :ok, null: false, default: false
      t.integer :http_status
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :attempts, null: false, default: 1
      t.integer :duration_ms
      t.text :error
      t.datetime :created_at, null: false
      t.index :created_at
    end
  end
end
