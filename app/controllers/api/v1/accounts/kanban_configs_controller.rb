class Api::V1::Accounts::KanbanConfigsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_config, except: [:index, :create]

  def index
    authorize KanbanConfig
    @kanban_config = Current.account.kanban_config
    unless @kanban_config
      @kanban_config = Current.account.build_kanban_config
      @kanban_config.save!
    end
    render json: @kanban_config
  end

  def show
    if @kanban_config.nil?
      @kanban_config = Current.account.build_kanban_config
      @kanban_config.save!
    end
    authorize @kanban_config
    render json: @kanban_config
  end

  def create
    @kanban_config = Current.account.build_kanban_config(kanban_config_params)
    authorize @kanban_config

    if @kanban_config.save
      render json: @kanban_config, status: :created
    else
      render json: { errors: @kanban_config.errors }, status: :unprocessable_entity
    end
  end

  def update
    # Se não existir configuração, criar uma nova
    unless @kanban_config
      @kanban_config = Current.account.build_kanban_config(kanban_config_params)
      authorize @kanban_config

      if @kanban_config.save
        render json: @kanban_config
        return
      else
        render json: { errors: @kanban_config.errors }, status: :unprocessable_entity
        return
      end
    end

    authorize @kanban_config

    # Fazer merge do config se estiver presente nos params
    params_hash = kanban_config_params.to_h
    if params_hash[:config].present?
      # Converter chaves de símbolo para string para fazer merge correto com JSONB
      existing_config = @kanban_config.config || {}
      new_config = params_hash[:config].stringify_keys
      params_hash[:config] = existing_config.merge(new_config)
    end

    if @kanban_config.update(params_hash)
      render json: @kanban_config
    else
      render json: { errors: @kanban_config.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @kanban_config
    @kanban_config.destroy!
    head :no_content
  end

  # Método para testar a conexão do webhook
  def test_webhook
    authorize @kanban_config

    return render json: { error: 'Webhook não configurado' }, status: :bad_request unless @kanban_config.webhook_enabled?

    begin
      test_payload = {
        event: 'kanban.webhook.test',
        data: {
          message: 'Teste de conexão do webhook',
          timestamp: Time.current.iso8601,
          account_id: Current.account.id,
          account_name: Current.account.name
        }
      }

      response = RestClient::Request.execute(
        method: :post,
        url: @kanban_config.webhook_url,
        payload: test_payload.to_json,
        headers: {
          content_type: :json,
          accept: :json,
          'User-Agent': 'Chatwoot-Kanban-Webhook/1.0'
        },
        timeout: 30
      )

      render json: {
        success: true,
        message: 'Webhook testado com sucesso!',
        response_code: response.code,
        response_body: response.body
      }
    rescue RestClient::Exception => e
      render json: {
        success: false,
        error: "Falha na conexão: #{e.message}",
        response_code: e.http_code,
        response_body: e.http_body
      }, status: :bad_request
    rescue StandardError => e
      render json: {
        success: false,
        error: "Erro: #{e.message}"
      }, status: :internal_server_error
    end
  end

  private

  def fetch_kanban_config
    @kanban_config = Current.account.kanban_config
    # Não renderizar erro aqui, apenas definir a variável
    # O erro será tratado no método que precisa da configuração
  end

  def kanban_config_params
    params.require(:kanban_config).permit(
      :enabled,
      :webhook_url,
      :webhook_secret,
      webhook_events: [],
      config: [
        :title,
        :default_view,
        :auto_assignment,
        :notifications_enabled,
        :support_email,
        :support_phone,
        :support_chat_hours,
        :support_chat_enabled,
        :dragbar_enabled,
        :quick_message_enabled,
        :list_view_enabled,
        :agenda_view_enabled
      ]
    )
  end
end
