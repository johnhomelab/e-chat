class AddNavigationFieldsToDashboardApps < ActiveRecord::Migration[6.1]
  def change
    add_column :dashboard_apps, :show_in_navigation, :boolean, default: false
    add_column :dashboard_apps, :icon, :string, default: 'preview-link'
  end
end 