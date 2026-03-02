# frozen_string_literal: true

require 'pathname'
# Carrega explicitamente o Stacklab::LicensingService antes de definir ChatwootApp.
# Isso garante que Stacklab::LicensingService esteja disponível globalmente.
# Este caminho relativo pressupõe que chatwoot_app.rb está em `lib/` e
# licensing_service.rb está em `stacklab/`, ambos na raiz do projeto.
begin
  require_relative '../stacklab/licensing_service'
rescue LoadError => e
  # Logar um erro crítico se o arquivo não puder ser carregado na inicialização.
  # A aplicação pode continuar em modo CE, mas isso deve ser investigado.
  Rails.logger.error "Falha CRÍTICA ao carregar '../stacklab/licensing_service.rb': #{e.message}. Funcionalidades StackLab PRO estarão desabilitadas."
end

module ChatwootApp
  def self.root
    Pathname.new(File.expand_path('..', __dir__))
  end

  def self.max_limit
    100_000
  end

  def self.enterprise?
    return if ENV.fetch('DISABLE_ENTERPRISE', false)

    @enterprise ||= root.join('enterprise').exist?
  end

  def self.chatwoot_cloud?
    enterprise? && GlobalConfig.get_value('DEPLOYMENT_ENV') == 'cloud'
  end

  def self.custom?
    @custom ||= root.join('custom').exist?
  end

  def self.help_center_root
    ENV.fetch('HELPCENTER_URL', nil) || ENV.fetch('FRONTEND_URL', nil)
  end

  def self.extensions
    if custom?
      %w[enterprise custom]
    elsif enterprise?
      %w[enterprise]
    else
      %w[]
    end
  end

  # Classe interna para fornecer acesso encapsulado às informações de licença StackLab
  class StacklabLicenseAccessor
    def initialize(service_loaded_successfully)
      @service_loaded = service_loaded_successfully
    end

    # O Kanban PRO está ativo?
    def kanban_pro_active?
      feature_enabled?(:kanban_pro)
    end

    # Uma feature específica está habilitada? (ex: :stacklab_modules, :cloud_configs)
    def feature_enabled?(feature_key)
      return false unless @service_loaded

      # Delega ao serviço de licenciamento real, usando :: para escopo global
      ::Stacklab::LicensingService.feature_enabled?(feature_key.to_sym)
    end

    # Qual é o plano atual? (ex: 'ce', 'pro')
    def plan
      return 'ce' unless @service_loaded

      ::Stacklab::LicensingService.current_plan
    end

    # Mensagem da API de licenciamento.
    def message
      return 'Serviço de licença StackLab indisponível.' unless @service_loaded

      ::Stacklab::LicensingService.license_message
    end

    # O token STACKLAB_TOKEN está configurado no ambiente?
    def token_configured?
      return false unless @service_loaded

      ::Stacklab::LicensingService.token_configured_in_env?
    end

    # Retorna todo o hash de features para fácil acesso (ex: no frontend).
    def all_features
      return {}.with_indifferent_access unless @service_loaded

      (::Stacklab::LicensingService.get_license_info[:features] || {}).with_indifferent_access
    end

    # O serviço de licenciamento StackLab está operacional e foi carregado?
    def service_available?
      @service_loaded
    end

    # Força a atualização do cache de licenças
    def refresh_license!
      ::Stacklab::LicensingService.clear_cache! if @service_loaded
      self
    end

    # NOVO MÉTODO: Verifica se o token é válido (mesmo que não seja plano PRO)
    def token_valid?
      return false unless @service_loaded

      ::Stacklab::LicensingService.token_valid?
    end

    # NOVO MÉTODO: Verifica se o plano atual é PRO
    def pro_plan?
      return false unless @service_loaded

      ::Stacklab::LicensingService.pro_plan?
    end
  end

  # Método interno para verificar se o serviço de licenciamento StackLab foi carregado.
  # Agora, apenas verifica se a constante está definida, pois o require_relative no topo deve ter feito o carregamento.
  def self.ensure_stacklab_service_loaded
    @_stacklab_service_loaded_status ||= begin
      if defined?(::Stacklab::LicensingService)
        true
      else
        false
      end
    rescue NameError => e # Adicionado para pegar NameError se ::Stacklab não estiver definido
      Rails.logger.error "NameError ao verificar ::Stacklab::LicensingService: #{e.message}. Funcionalidades PRO desabilitadas."
      false
    end
  end

  # PONTO DE ENTRADA UNIFICADO para informações de licenciamento StackLab.
  # Retorna uma instância de StacklabLicenseAccessor.
  def self.stacklab
    service_loaded = ensure_stacklab_service_loaded
    # Sempre retorna um accessor; os métodos do accessor verificarão service_loaded.
    StacklabLicenseAccessor.new(service_loaded)
  end

  # MÉTODO EXISTENTE (agora com nova lógica): Verifica se a funcionalidade principal do StackLab (Kanban PRO) está ativa.
  def self.stacklab?
    stacklab.kanban_pro_active?
  end
  
  def self.advanced_search_allowed?
    enterprise? && ENV.fetch('OPENSEARCH_URL', nil).present?
  end

  def self.otel_enabled?
    otel_provider = InstallationConfig.find_by(name: 'OTEL_PROVIDER')&.value
    secret_key = InstallationConfig.find_by(name: 'LANGFUSE_SECRET_KEY')&.value

    otel_provider.present? && secret_key.present? && otel_provider == 'langfuse'
  end
end
