class CreateKanbanAutomations < ActiveRecord::Migration[7.0]
  def change
    create_table :kanban_automations do |t|
      t.string :name
      t.text :description
      t.boolean :active, default: true
      t.jsonb :trigger, default: {}
      t.jsonb :conditions, default: []
      t.jsonb :actions, default: []
      t.references :account, null: false, foreign_key: true

      t.timestamps
    end

    add_index :kanban_automations, [:account_id, :name]
  end
end
