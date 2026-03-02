# stacklab/licensing_service.rb
require 'httparty' # Certifique-se de que httparty está no Gemfile
require 'json'     # Para JSON.parse, embora HTTParty geralmente lide com isso

module Stacklab
  module LicensingService
    API_ENDPOINT = ENV.fetch('STACKLAB_API_VERIFY_URL', 'https://pulse.stacklab.digital/api/cw/licenses/verify').freeze
    # Cache de 1 hora por padrão, pode ser configurado via ENV
    CACHE_DURATION = ENV.fetch('STACKLAB_LICENSE_CACHE_MINUTES', 60).to_i.minutes
    # Timeout para a chamada da API, em segundos
    API_TIMEOUT = ENV.fetch('STACKLAB_API_TIMEOUT_SECONDS', 10).to_i

    # Lock para operações de cache, para evitar race conditions em ambientes com threads.
    @cache_lock = Mutex.new
    @cached_license_info = nil
    @last_cache_time = nil

    def self.get_license_info(force_refresh: false)
      token = ENV.fetch('STACKLAB_TOKEN', nil)

      unless token.present?
        # Se não há token, não há necessidade de cache ou chamada de API.
        # Retorna uma estrutura consistente com a resposta esperada.
        return default_ce_response('STACKLAB_TOKEN não configurado no ambiente.')
      end

      # Operações de cache e API dentro de um lock para thread-safety
      @cache_lock.synchronize do
        if !force_refresh && @cached_license_info && @last_cache_time && (Time.current - @last_cache_time < CACHE_DURATION)
          # Log para indicar que o cache está sendo usado
          # Rails.logger.debug "[Stacklab::LicensingService] Usando informações de licença cacheadas."
          return @cached_license_info
        end

        # Log para indicar que uma chamada à API será feita
        Rails.logger.info "[Stacklab::LicensingService] Cache expirado ou refresh forçado. Chamando API de licença em: #{API_ENDPOINT}"

        begin
          response = HTTParty.post(
            API_ENDPOINT,
            body: { token: token }.to_json,
            headers: { 'Content-Type' => 'application/json', 'Accept' => 'application/json' },
            timeout: API_TIMEOUT
          )

          if response.success? && response.parsed_response.is_a?(Hash)
            parsed_body = response.parsed_response.transform_keys(&:to_sym) # Garante chaves como símbolos

            # Inicializa as features com valores padrão (todas desabilitadas)
            # Estas são as chaves internas que o sistema espera.
            final_processed_features = {
              kanban_pro: false,
              stacklab_modules: false,
              cloud_configs: false
            }

            features_data_from_api = parsed_body[:features]

            if features_data_from_api.is_a?(String)
              begin
                # A API retorna 'features' como uma string JSON. Ex: "{"Kanban":"go","Modulos":"false","Cloud configs":"false","Limit":"1"}"
                # Parseia essa string JSON aninhada.
                api_level_features = JSON.parse(features_data_from_api).transform_keys(&:to_sym)

                # Log para debug das chaves antes e depois da transformação
                Rails.logger.info "[Stacklab::LicensingService] Features antes de transform_keys: #{JSON.parse(features_data_from_api).keys.inspect}"
                Rails.logger.info "[Stacklab::LicensingService] Features depois de transform_keys: #{api_level_features.keys.inspect}"
                Rails.logger.info "[Stacklab::LicensingService] Valor bruto de :kanban: #{api_level_features[:kanban].inspect}"

                # Mapeia os valores da API para as chaves de feature internas e converte para booleano.
                # Kanban PRO é true quando o valor é "pro" OU "go"
                kanban_value = api_level_features[:kanban]&.to_s&.downcase
                final_processed_features[:kanban_pro] = (kanban_value == 'pro' || kanban_value == 'go')

                # Log detalhado para debug
                Rails.logger.info "[Stacklab::LicensingService] Valor Kanban da API: '#{api_level_features[:kanban]}' -> downcase: '#{kanban_value}' -> kanban_pro: #{final_processed_features[:kanban_pro]}"

                # StackLab modules é true quando o valor é "true" (string)
                final_processed_features[:stacklab_modules] = (api_level_features[:modulos]&.to_s&.downcase == 'true')
                # Cloud configs é true quando o valor é "true" (string)
                final_processed_features[:cloud_configs] = (api_level_features[:cloud_configs]&.to_s&.downcase == 'true')

                # Log para debug das features mapeadas
                Rails.logger.info "[Stacklab::LicensingService] Features mapeadas da API: #{api_level_features.inspect}"
                Rails.logger.info "[Stacklab::LicensingService] Features processadas: #{final_processed_features.inspect}"
              rescue JSON::ParserError => e
                Rails.logger.error "[Stacklab::LicensingService] Erro ao parsear string JSON de features da API: #{e.message}. String recebida: '#{features_data_from_api}'"
                # Em caso de erro no parse, as features permanecem com seus valores padrão (false).
              end
            elsif features_data_from_api.is_a?(Hash)
              # Fallback caso a API mude para enviar 'features' como um hash diretamente.
              api_level_features = features_data_from_api.transform_keys(&:to_sym)
              kanban_value = api_level_features[:kanban]&.to_s&.downcase
              final_processed_features[:kanban_pro] = (kanban_value == 'pro' || kanban_value == 'go')

              # Log detalhado para debug
              Rails.logger.info "[Stacklab::LicensingService] [HASH] Valor Kanban da API: '#{api_level_features[:kanban]}' -> downcase: '#{kanban_value}' -> kanban_pro: #{final_processed_features[:kanban_pro]}"

              final_processed_features[:stacklab_modules] = (api_level_features[:modulos]&.to_s&.downcase == 'true')
              final_processed_features[:cloud_configs] = (api_level_features[:cloud_configs]&.to_s&.downcase == 'true')
            else
              unless features_data_from_api.nil? # Não logar aviso se features não vier (opcional)
                Rails.logger.warn "[Stacklab::LicensingService] 'features' da API não é String nem Hash: #{features_data_from_api.inspect}. Usando features padrão desabilitadas."
              end
              # Features permanecem com seus valores padrão (false).
            end

            @cached_license_info = {
              token_provided: true,
              plan: (parsed_body[:plan] || 'ce').to_s,
              features: final_processed_features.with_indifferent_access, # Usar as features processadas
              message: (parsed_body[:message] || 'Resposta da API não continha mensagem.').to_s,
              raw_response: parsed_body # Mantém a resposta original (já parseada do JSON principal) para debug
            }.with_indifferent_access
          else
            error_message = "Erro na API de licença StackLab: Código #{response.code}"
            error_message += " - Corpo: #{response.body}" if response.body.present?
            Rails.logger.error error_message
            @cached_license_info = default_ce_response("Erro na API de licença: Código #{response.code}", response.try(:parsed_response),
                                                       token_was_provided: true)
          end
        rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout, StandardError => e
          # Captura uma gama mais ampla de exceções de rede e HTTParty
          Rails.logger.error "Exceção ao contatar API de licença StackLab: #{e.class.name} - #{e.message}"
          @cached_license_info = default_ce_response("Exceção ao contatar API de licença: #{e.class.name}", nil, token_was_provided: true)
        end

        @last_cache_time = Time.current
        return @cached_license_info # Retorna dentro do synchronize
      end # Fim do @cache_lock.synchronize
    end

    def self.feature_enabled?(feature_key)
      info = get_license_info
      # A feature só está habilitada se um token foi fornecido E a API confirmou a feature.
      info[:token_provided] && info.dig(:features, feature_key.to_sym) == true
    end

    def self.current_plan
      get_license_info[:plan]
    end

    def self.license_message
      get_license_info[:message]
    end

    def self.token_configured_in_env?
      ENV['STACKLAB_TOKEN'].present?
    end

    # NOVO MÉTODO: Verifica se o token é válido (mesmo que não seja plano PRO)
    def self.token_valid?
      info = get_license_info
      # Token é válido se foi fornecido E a API respondeu com sucesso
      info[:token_provided] && info[:raw_response].present?
    end

    # NOVO MÉTODO: Verifica se o plano atual é PRO
    def self.pro_plan?
      current_plan.to_s.downcase == 'pro'
    end

    def self.clear_cache!
      @cache_lock.synchronize do
        @cached_license_info = nil
        @last_cache_time = nil
      end
      Rails.logger.info 'Cache de licença StackLab limpo.'
    end

    def self.default_ce_response(message, raw_api_response = nil, token_was_provided: false)
      {
        token_provided: token_was_provided,
        plan: 'ce',
        features: { kanban_pro: false, stacklab_modules: false, cloud_configs: false }.with_indifferent_access,
        message: message.to_s,
        raw_response: raw_api_response
      }.with_indifferent_access
    end
  end
end
