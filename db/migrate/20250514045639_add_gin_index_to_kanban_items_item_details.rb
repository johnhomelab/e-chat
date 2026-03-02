class AddGinIndexToKanbanItemsItemDetails < ActiveRecord::Migration[7.0]
  def change
    add_index :kanban_items, :item_details, using: :gin
  end
end
