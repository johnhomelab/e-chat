class UpdateInstallationPricingPlanToEnterprise < ActiveRecord::Migration[6.1]
  def up
    # Atualizando o plano para enterprise
    plan_config = InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN')
    if plan_config
      plan_config.update!(
        serialized_value: ActiveSupport::HashWithIndifferentAccess.new(
          value: 'enterprise'
        )
      )
    end

    # Atualizando a quantidade de licenças para 10000
    quantity_config = InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY')
    if quantity_config
      quantity_config.update!(
        serialized_value: ActiveSupport::HashWithIndifferentAccess.new(
          value: 10000
        )
      )
    end
  end

  def down
    # Revertendo o plano para community
    plan_config = InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN')
    if plan_config
      plan_config.update!(
        serialized_value: ActiveSupport::HashWithIndifferentAccess.new(
          value: 'community'
        )
      )
    end

    # Revertendo a quantidade de licenças para o valor padrão
    quantity_config = InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY')
    if quantity_config
      quantity_config.update!(
        serialized_value: ActiveSupport::HashWithIndifferentAccess.new(
          value: 0
        )
      )
    end
  end
end