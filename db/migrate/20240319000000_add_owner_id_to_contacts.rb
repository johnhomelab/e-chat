class AddOwnerIdToContacts < ActiveRecord::Migration[7.0]
  def change
    add_column :contacts, :owner_id, :integer, null: true
    add_index :contacts, :owner_id
    add_foreign_key :contacts, :users, column: :owner_id
  end
end 