class RemoveOwnerIdFromContacts < ActiveRecord::Migration[7.0]
  def change
    remove_foreign_key :contacts, :users, column: :owner_id
    remove_index :contacts, :owner_id
    remove_column :contacts, :owner_id, :integer
  end
end 