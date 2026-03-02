class UpdateInstallationConfigFeatureFlags < ActiveRecord::Migration[6.1]
  def up
    features = YAML.load_file(Rails.root.join('config', 'features.yml'))
    
    # Convert features to the expected format with HashWithIndifferentAccess
    formatted_features = features.map do |feature|
      feature.deep_symbolize_keys.with_indifferent_access
    end

    # Create the serialized value in the expected format
    serialized_value = {
      value: formatted_features
    }.with_indifferent_access

    # Update or create the ACCOUNT_LEVEL_FEATURE_DEFAULTS config
    installation_config = InstallationConfig.find_or_initialize_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    installation_config.serialized_value = serialized_value
    installation_config.save!

    # Update existing accounts to reset feature flags to 0
    execute <<-SQL
      UPDATE accounts 
      SET feature_flags = 274910936719
      WHERE feature_flags IS NOT NULL;
    SQL
  end

  def down
    # This migration is not reversible
    raise ActiveRecord::IrreversibleMigration
  end
end 