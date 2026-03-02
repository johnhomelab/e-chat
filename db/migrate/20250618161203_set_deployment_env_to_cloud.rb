class SetDeploymentEnvToCloud < ActiveRecord::Migration[7.0]
  def up
    config = InstallationConfig.find_or_initialize_by(name: 'DEPLOYMENT_ENV')
    config.value = 'cloud'
    config.save!
  end

  def down
    config = InstallationConfig.find_or_initialize_by(name: 'DEPLOYMENT_ENV')
    config.value = 'self-hosted'
    config.save!
  end
end
