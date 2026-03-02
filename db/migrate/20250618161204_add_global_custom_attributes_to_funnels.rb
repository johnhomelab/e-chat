class AddGlobalCustomAttributesToFunnels < ActiveRecord::Migration[6.1]
  def change
    add_column :funnels, :global_custom_attributes, :jsonb, default: [], null: false
  end
end 