class SuperAdmin::DashboardScriptsController < SuperAdmin::ApplicationController
  def show
    @dashboard_scripts = InstallationConfig.find_by(name: 'DASHBOARD_SCRIPTS')&.value
    @logout_redirect_link = InstallationConfig.find_by(name: 'LOGOUT_REDIRECT_LINK')&.value
  end

  def create
    handle_script_update
    redirect_to super_admin_dashboard_scripts_path, notice: 'Modulos StackLab atualizados com sucesso'
  end

  def stacklab_ai
    # Método para renderizar a view do StackLab AI
  end

  def generate_script
    prompt = params[:prompt]

    if prompt.blank?
      render json: { error: 'Prompt não pode estar vazio' }, status: :unprocessable_entity
      return
    end

    begin
      context_data = {
        user_id: current_user&.id,
        user_email: current_user&.email,
        user_name: current_user&.name,
        account_id: current_user&.account&.id,
        account_name: current_user&.account&.name,
        host: request.host,
        protocol: request.protocol,
        user_agent: request.user_agent,
        remote_ip: request.remote_ip,
        timestamp: Time.current.iso8601,
        rails_env: Rails.env,
        chatwoot_version: (defined?(VERSION_CW) ? VERSION_CW : 'unknown')
      }

      response = call_stacklab_ai_api(prompt, context_data)
      render json: { script: response, success: true }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Erro ao chamar StackLab AI API: #{e.message}")
      render json: { error: 'Erro interno do servidor' }, status: :internal_server_error
    end
  end

  def update_logout_redirect
    logout_redirect_link = params[:logout_redirect_link] || '/app/login'
    
    i = InstallationConfig.where(name: 'LOGOUT_REDIRECT_LINK').first_or_initialize
    i.locked = false
    i.value = logout_redirect_link
    i.save!
    
    redirect_to super_admin_dashboard_scripts_path, notice: 'URL de redirecionamento atualizada com sucesso'
  rescue StandardError => e
    Rails.logger.error("Erro ao atualizar LOGOUT_REDIRECT_LINK: #{e.message}")
    redirect_to super_admin_dashboard_scripts_path, alert: 'Erro ao atualizar URL de redirecionamento'
  end

  private

  def call_stacklab_ai_api(prompt, context_data = {})
    require 'net/http'
    require 'uri'
    require 'json'

    uri = URI('https://webhook.stacklab.digital/webhook/modules-ai')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['User-Agent'] = 'Chatwoot-StackLab-AI/1.0'

    # Payload com prompt e dados contextuais
    payload = {
      prompt: prompt,
      context: context_data
    }

    request.body = payload.to_json

    Rails.logger.info("StackLab API Request - URL: #{uri}")
    Rails.logger.info("StackLab API Request - Body: #{request.body}")

    response = http.request(request)

    Rails.logger.info("StackLab API Response - Status: #{response.code}")
    Rails.logger.info("StackLab API Response - Body: #{response.body}")

    if response.code.to_i == 200
      # A API StackLab retorna o script diretamente, não JSON
      response.body
    else
      raise "Erro na API StackLab: #{response.code} - #{response.body}"
    end
  rescue JSON::ParserError => e
    Rails.logger.error("Erro ao parsear resposta JSON da API StackLab: #{e.message}")
    raise "Erro ao processar resposta da API StackLab"
  rescue Net::OpenTimeout => e
    Rails.logger.error("Timeout de conexão com API StackLab: #{e.message}")
    raise "Timeout ao conectar com API StackLab"
  rescue Net::ReadTimeout => e
    Rails.logger.error("Timeout de leitura da API StackLab: #{e.message}")
    raise "Timeout ao ler resposta da API StackLab"
  rescue StandardError => e
    Rails.logger.error("Erro genérico na chamada da API StackLab: #{e.message}")
    raise "Erro interno na comunicação com API StackLab"
  end

  private

  def handle_script_update
    script_value = params[:dashboard_scripts]
    
    # Garantir que o script esteja em um formato seguro
    script_value = '' if script_value.nil?
    
    # Usar first_or_initialize para encontrar ou criar a configuração
    i = InstallationConfig.where(name: 'DASHBOARD_SCRIPTS').first_or_initialize
    i.locked = false # Garantir que não está bloqueado
    i.value = script_value # Usar o setter para garantir o formato correto
    i.save!
  end
end

SuperAdmin::DashboardScriptsController.prepend_mod_with('SuperAdmin::DashboardScriptsController') 