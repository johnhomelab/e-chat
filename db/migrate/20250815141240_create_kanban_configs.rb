class CreateKanbanConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :kanban_configs do |t|
      t.references :account, null: false, foreign_key: true
      t.jsonb :config, null: false, default: {}
      t.boolean :enabled, default: true
      t.string :webhook_url
      t.string :webhook_secret
      t.jsonb :webhook_events, default: []

      t.timestamps
    end

    add_index :kanban_configs, :config, using: :gin
    add_index :kanban_configs, :webhook_events, using: :gin
  end
end
