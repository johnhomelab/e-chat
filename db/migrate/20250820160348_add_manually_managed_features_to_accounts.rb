class AddManuallyManagedFeaturesToAccounts < ActiveRecord::Migration[7.2]
  def change
    unless column_exists?(:accounts, :manually_managed_features)
      add_column :accounts, :manually_managed_features, :jsonb
    end
  end
end
