class AddChecklistToKanbanItems < ActiveRecord::Migration[7.2]
  def up
    # Adicionar o novo campo checklist
    add_column :kanban_items, :checklist, :jsonb, default: []

    # Migrar dados existentes do item_details['checklist'] para o novo campo checklist
    KanbanItem.reset_column_information

    KanbanItem.find_each do |kanban_item|
      if kanban_item.item_details.is_a?(Hash) && kanban_item.item_details['checklist'].present?
        # Mover o checklist para o novo campo
        kanban_item.update_column(:checklist, kanban_item.item_details['checklist'])

        # Remover o checklist do item_details
        item_details_without_checklist = kanban_item.item_details.except('checklist')
        kanban_item.update_column(:item_details, item_details_without_checklist)
      end
    end

    # Adicionar índice GIN para o novo campo checklist
    add_index :kanban_items, :checklist, using: :gin
  end

  def down
    # Migrar dados de volta para item_details
    KanbanItem.reset_column_information

    KanbanItem.find_each do |kanban_item|
      if kanban_item.checklist.present?
        # Mover o checklist de volta para item_details
        item_details_with_checklist = kanban_item.item_details.merge('checklist' => kanban_item.checklist)
        kanban_item.update_column(:item_details, item_details_with_checklist)
      end
    end

    # Remover o índice
    remove_index :kanban_items, :checklist

    # Remover o campo checklist
    remove_column :kanban_items, :checklist
  end
end
