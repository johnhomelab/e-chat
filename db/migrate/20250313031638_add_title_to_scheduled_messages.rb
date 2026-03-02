class AddTitleToScheduledMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :scheduled_messages, :title, :string
  end
end
