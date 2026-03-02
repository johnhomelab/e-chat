class SuperAdmin::CloudConfigsController < SuperAdmin::ApplicationController
  def show
    fetch_installation_configs
    @app_config = {}
    @allowed_configs.each do |config|
      @app_config[config] = InstallationConfig.find_by(name: config)&.value
    end
  end

  def create
    fetch_installation_configs
    handle_configs_update
    redirect_to super_admin_cloud_configs_path, notice: 'Config updated successfully'
  end

  private

  def handle_configs_update
    params[:app_config].each do |key, value|
      next unless @allowed_configs.include?(key)
      
      # Handle JSON strings from hidden fields
      if key == "CHATWOOT_CLOUD_PLAN_FEATURES"
        begin
          parsed_value = JSON.parse(value)
          
          # Garantir formato correto: hash onde as chaves são nomes de planos
          # e os valores são arrays de features
          if parsed_value.is_a?(Array)
            # Se for um array simples, converter para o formato esperado
            # Considerando que todos os planos terão as mesmas features
            cloud_plans = InstallationConfig.find_by(name: 'CHATWOOT_CLOUD_PLANS')&.value || []
            features_hash = {}
            
            if cloud_plans.present? && cloud_plans.is_a?(Array)
              cloud_plans.each do |plan|
                plan_name = plan['name']
                features_hash[plan_name] = parsed_value if plan_name.present?
              end
            end
            
            # Adicionar ao plano padrão se nenhum plano for encontrado
            features_hash['default'] = parsed_value if features_hash.empty?
            value = features_hash
          elsif !parsed_value.is_a?(Hash)
            value = { 'default' => [] }
          else
            value = parsed_value
          end
        rescue JSON::ParserError
          value = { 'default' => [] }
        end
      elsif key == "CHATWOOT_CLOUD_PLANS"
        # Garantir que o valor seja sempre um array válido de objetos de plano
        begin
          parsed_value = JSON.parse(value)
          value = parsed_value.is_a?(Array) ? parsed_value : []
        rescue JSON::ParserError
          value = []
        end
      end

      # Usar first_or_initialize em vez de first_or_create para evitar salvar em dois passos
      i = InstallationConfig.where(name: key).first_or_initialize
      i.locked = false # Garantir que não está bloqueado
      i.value = value  # Usar o setter para garantir o formato correto
      i.save!
    end
  end

  def fetch_installation_configs
    @installation_configs = {}
    InstallationConfig.all.each do |config|
      @installation_configs[config.name] = {
        'display_title' => config.name.titleize,
        'type' => 'string'
      }
    end

    # Adicionar descrições específicas e tipos para cada configuração
    @installation_configs['CHATWOOT_CLOUD_PLANS'] = {
      'display_title' => 'Cloud Plans',
      'type' => 'plans_list',
      'description' => 'Configure os planos disponíveis para os usuários da nuvem, incluindo IDs de produto e preço do Stripe.'
    }

    @installation_configs['CHATWOOT_CLOUD_PLAN_FEATURES'] = {
      'display_title' => 'Plan Features',
      'type' => 'feature_list',
      'description' => 'Lista de recursos disponíveis para os usuários com planos pagos. Estas features serão atribuídas a todos os planos configurados.'
    }

    @installation_configs['DEPLOYMENT_ENV'] = {
      'display_title' => 'Deployment Environment',
      'type' => 'select',
      'description' => 'Define como o Chatwoot será executado. O modo cloud oferece integração nativa com o Stripe para gerenciamento de contas e assinaturas.',
      'options' => [
        { 'label' => 'Cloud', 'value' => 'cloud', 'description' => 'Com integração Stripe e gerenciamento de assinaturas' },
        { 'label' => 'Self-hosted', 'value' => 'self_hosted', 'description' => 'Instalação local sem integração com provedores externos' }
      ]
    }

    @allowed_configs = ['CHATWOOT_CLOUD_PLANS', 'CHATWOOT_CLOUD_PLAN_FEATURES', 'DEPLOYMENT_ENV']
  end
end

SuperAdmin::CloudConfigsController.prepend_mod_with('SuperAdmin::CloudConfigsController') 