class CreateScheduledMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :scheduled_messages do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :content, null: false
      t.datetime :scheduled_at, null: false
      t.string :status, default: 'pending'
      t.timestamps
    end

    add_index :scheduled_messages, :scheduled_at
    add_index :scheduled_messages, :status
  end
end 