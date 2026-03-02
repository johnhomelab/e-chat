class AddIsRecurrentToScheduledMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :scheduled_messages, :is_recurrent, :boolean
    add_column :scheduled_messages, :period, :jsonb
  end
end
