class Api::V1::Accounts::InboxesController < Api::V1::Accounts::BaseController
  include Api::V1::InboxesHelper
  before_action :fetch_inbox, except: [:index, :create]
  before_action :fetch_agent_bot, only: [:set_agent_bot]
  before_action :validate_limit, only: [:create]
  # we are already handling the authorization in fetch inbox
  before_action :check_authorization, except: [:show, :health, :generate_qrcode, :restart_instance, :connection_state, :logout_instance, :server_url]
  before_action :validate_whatsapp_cloud_channel, only: [:health]

  def index
    @inboxes = policy_scope(Current.account.inboxes.order_by_name.includes(:channel, { avatar_attachment: [:blob] }))
  end

  def show; end

  # Deprecated: This API will be removed in 2.7.0
  def assignable_agents
    @assignable_agents = @inbox.assignable_agents
  end

  def campaigns
    @campaigns = @inbox.campaigns
  end

  def avatar
    @inbox.avatar.attachment.destroy! if @inbox.avatar.attached?
    head :ok
  end

  def create
    ActiveRecord::Base.transaction do
      channel = create_channel
      @inbox = Current.account.inboxes.build(
        {
          name: inbox_name(channel),
          channel: channel
        }.merge(
          permitted_params.except(:channel)
        )
      )
      @inbox.save!
    end
  end

  def update
    inbox_params = permitted_params.except(:channel, :csat_config)
    inbox_params[:csat_config] = format_csat_config(permitted_params[:csat_config]) if permitted_params[:csat_config].present?
    @inbox.update!(inbox_params)
    update_inbox_working_hours
    update_channel if channel_update_required?
  end

  def agent_bot
    @agent_bot = @inbox.agent_bot
  end

  def set_agent_bot
    if @agent_bot
      agent_bot_inbox = @inbox.agent_bot_inbox || AgentBotInbox.new(inbox: @inbox)
      agent_bot_inbox.agent_bot = @agent_bot
      agent_bot_inbox.save!
    elsif @inbox.agent_bot_inbox.present?
      @inbox.agent_bot_inbox.destroy!
    end
    head :ok
  end

  def destroy
    ::DeleteObjectJob.perform_later(@inbox, Current.user, request.ip) if @inbox.present?
    render status: :ok, json: { message: I18n.t('messages.inbox_deletetion_response') }
  end

  def sync_templates
    return render status: :unprocessable_entity, json: { error: 'Template sync is only available for WhatsApp channels' } unless whatsapp_channel?

    trigger_template_sync
    render status: :ok, json: { message: 'Template sync initiated successfully' }
  rescue StandardError => e
    render status: :internal_server_error, json: { error: e.message }
  end

  def health
    health_data = Whatsapp::HealthService.new(@inbox.channel).fetch_health_status
    render json: health_data
  rescue StandardError => e
    Rails.logger.error "[INBOX HEALTH] Error fetching health data: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def generate_qrcode
    unofficial_provider = GlobalConfigService.load('WHATSAPP_UNOFFICIAL_API_PROVIDER', nil)
    Rails.logger.info "[QR CODE] Unofficial provider: #{unofficial_provider.inspect}"
    
    unless unofficial_provider == 'evolution'
      Rails.logger.error "[QR CODE] Unofficial API provider not configured or not evolution: #{unofficial_provider.inspect}"
      return render json: { error: 'Unofficial API provider not configured or not set to evolution' }, status: :unprocessable_entity
    end

    server_url = GlobalConfigService.load('EVOLUTION_SERVER_URL', nil)
    api_key = GlobalConfigService.load('EVOLUTION_API_KEY', nil)

    if server_url.blank? || api_key.blank?
      Rails.logger.error "[QR CODE] Evolution server URL or API key not configured"
      return render json: { error: 'Evolution server URL or API key not configured' }, status: :unprocessable_entity
    end

    # Generate instance identifier: account_{account_id}_{sanitized_inbox_name}
    sanitized_name = @inbox.name.parameterize(separator: '_')
    instance = "account_#{Current.account.id}_#{sanitized_name}"
    
    Rails.logger.info "[QR CODE] Server URL: #{server_url.present? ? 'present' : 'blank'}, API Key: #{api_key.present? ? 'present' : 'blank'}, Instance: #{instance}"

    # Check if instance exists
    fetch_response = Evolution.fetch_instance(server_url, instance, api_key)
    Rails.logger.info "[QR CODE] Instance fetch response: exists=#{fetch_response[:exists]}, code=#{fetch_response[:code]}"

    # Create instance if it doesn't exist
    unless fetch_response[:exists]
      Rails.logger.info "[QR CODE] Instance does not exist, creating: #{instance}"
      
      # Prepare Chatwoot integration options
      frontend_url = ENV.fetch('FRONTEND_URL', nil)
      
      # Ensure user has access token
      user_token = if Current.user.present?
        Current.user.access_token || Current.user.create_access_token
        Current.user.access_token.token
      else
        ''
      end
      
      chatwoot_options = {
        enabled: true,
        account_id: Current.account.id.to_s,
        token: user_token,
        url: frontend_url || '',
        sign_msg: true,
        reopen_conversation: true,
        conversation_pending: true,
        name_inbox: @inbox.name,
        merge_brazil_contacts: true,
        import_contacts: true,
        import_messages: true,
        days_limit_import_messages: 30,
        sign_delimiter: "\n",
        auto_create: true,
        organization: Current.account.name || '',
        logo: '',
        ignore_jids: []
      }
      
      create_response = Evolution.create_instance(server_url, instance, api_key, chatwoot: chatwoot_options)
      
      # If creation fails with Forbidden, instance might already exist in connecting state
      # In this case, proceed to connect_instance which will generate a new QR code
      unless create_response[:success]
        if create_response[:code] == 403
          Rails.logger.info "[QR CODE] Instance creation returned Forbidden, instance may already exist in connecting state. Proceeding to connect."
        else
          error_msg = create_response[:error] || 'Failed to create instance'
          Rails.logger.error "[QR CODE] Failed to create instance: #{error_msg}"
          return render json: { error: "Failed to create Evolution instance: #{error_msg}" }, status: :unprocessable_entity
        end
      else
        Rails.logger.info "[QR CODE] Instance created successfully: #{instance}"
        
        if create_response[:chatwoot_setup]
          if create_response[:chatwoot_setup][:success]
            Rails.logger.info "[QR CODE] Chatwoot integration configured successfully"
          else
            Rails.logger.error "[QR CODE] Failed to configure Chatwoot integration: #{create_response[:chatwoot_setup][:error]}"
          end
        end
      end
    end

    # Generate QR code
    response = Evolution.connect_instance(server_url, instance, api_key)
    Rails.logger.info "[QR CODE] Evolution API response: success=#{response[:success]}, code=#{response[:code]}"
    
    if response[:success]
      begin
        qr_data = JSON.parse(response[:body])
        render json: qr_data
      rescue JSON::ParserError => e
        Rails.logger.error "[QR CODE] Error parsing success response: #{e.message}"
        Rails.logger.error "[QR CODE] Response body: #{response[:body]}"
        render json: { error: 'Invalid response format from Evolution API' }, status: :unprocessable_entity
      end
    else
      error_msg = response[:error] || 'Failed to generate QR code'
      
      case response[:code]
      when 404
        error_msg = "Instance '#{instance}' not found on Evolution server. Please create the instance first."
      when 401, 403
        error_msg = 'Invalid API key or unauthorized access to Evolution server'
      when 500..599
        error_msg = "Evolution server error (HTTP #{response[:code]}). Please try again later."
      when 0
        error_msg = response[:error] || 'Failed to connect to Evolution server'
      else
        error_msg = response[:error] || "Evolution API error (HTTP #{response[:code]})"
      end
      
      Rails.logger.error "[QR CODE] Evolution API failed: code=#{response[:code]}, error=#{error_msg}"
      Rails.logger.error "[QR CODE] Response body: #{response[:body]}" if response[:body].present?
      
      render json: { error: error_msg }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "[QR CODE] Unexpected error: #{e.class} - #{e.message}"
    Rails.logger.error "[QR CODE] Backtrace: #{e.backtrace.first(5).join("\n")}"
    render json: { error: "An unexpected error occurred: #{e.message}" }, status: :internal_server_error
  end

  def restart_instance
    unofficial_provider = GlobalConfigService.load('WHATSAPP_UNOFFICIAL_API_PROVIDER', nil)
    
    unless unofficial_provider == 'evolution'
      return render json: { error: 'Unofficial API provider not configured or not set to evolution' }, status: :unprocessable_entity
    end

    server_url = GlobalConfigService.load('EVOLUTION_SERVER_URL', nil)
    api_key = GlobalConfigService.load('EVOLUTION_API_KEY', nil)

    if server_url.blank? || api_key.blank?
      return render json: { error: 'Evolution server URL or API key not configured' }, status: :unprocessable_entity
    end

    sanitized_name = @inbox.name.parameterize(separator: '_')
    instance = "account_#{Current.account.id}_#{sanitized_name}"

    response = Evolution.restart_instance(server_url, instance, api_key)
    
    if response[:success]
      begin
        instance_data = JSON.parse(response[:body])
        render json: instance_data
      rescue JSON::ParserError
        render json: { error: 'Invalid response format from Evolution API' }, status: :unprocessable_entity
      end
    else
      error_msg = response[:error] || 'Failed to restart instance'
      render json: { error: error_msg }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "[RESTART INSTANCE] Unexpected error: #{e.class} - #{e.message}"
    render json: { error: "An unexpected error occurred: #{e.message}" }, status: :internal_server_error
  end

  def connection_state
    unofficial_provider = GlobalConfigService.load('WHATSAPP_UNOFFICIAL_API_PROVIDER', nil)
    
    unless unofficial_provider == 'evolution'
      return render json: { error: 'Unofficial API provider not configured or not set to evolution' }, status: :unprocessable_entity
    end

    server_url = GlobalConfigService.load('EVOLUTION_SERVER_URL', nil)
    api_key = GlobalConfigService.load('EVOLUTION_API_KEY', nil)

    if server_url.blank? || api_key.blank?
      return render json: { error: 'Evolution server URL or API key not configured' }, status: :unprocessable_entity
    end

    sanitized_name = @inbox.name.parameterize(separator: '_')
    instance = "account_#{Current.account.id}_#{sanitized_name}"

    response = Evolution.connection_state(server_url, instance, api_key)
    
    if response[:success]
      begin
        connection_data = JSON.parse(response[:body])
        render json: connection_data
      rescue JSON::ParserError
        render json: { error: 'Invalid response format from Evolution API' }, status: :unprocessable_entity
      end
    else
      error_msg = response[:error] || 'Failed to check connection state'
      render json: { error: error_msg }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "[CONNECTION STATE] Unexpected error: #{e.class} - #{e.message}"
    render json: { error: "An unexpected error occurred: #{e.message}" }, status: :internal_server_error
  end

  def logout_instance
    unofficial_provider = GlobalConfigService.load('WHATSAPP_UNOFFICIAL_API_PROVIDER', nil)
    
    unless unofficial_provider == 'evolution'
      return render json: { error: 'Unofficial API provider not configured or not set to evolution' }, status: :unprocessable_entity
    end

    server_url = GlobalConfigService.load('EVOLUTION_SERVER_URL', nil)
    api_key = GlobalConfigService.load('EVOLUTION_API_KEY', nil)

    if server_url.blank? || api_key.blank?
      return render json: { error: 'Evolution server URL or API key not configured' }, status: :unprocessable_entity
    end

    sanitized_name = @inbox.name.parameterize(separator: '_')
    instance = "account_#{Current.account.id}_#{sanitized_name}"

    response = Evolution.logout_instance(server_url, instance, api_key)
    
    if response[:success]
      begin
        logout_data = JSON.parse(response[:body])
        render json: logout_data
      rescue JSON::ParserError
        render json: { error: 'Invalid response format from Evolution API' }, status: :unprocessable_entity
      end
    else
      error_msg = response[:error] || 'Failed to logout instance'
      render json: { error: error_msg }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "[LOGOUT INSTANCE] Unexpected error: #{e.class} - #{e.message}"
    render json: { error: "An unexpected error occurred: #{e.message}" }, status: :internal_server_error
  end

  def server_url
    unofficial_provider = GlobalConfigService.load('WHATSAPP_UNOFFICIAL_API_PROVIDER', nil)
    
    unless unofficial_provider == 'evolution'
      return render json: { error: 'Unofficial API provider not configured or not set to evolution' }, status: :unprocessable_entity
    end

    server_url = GlobalConfigService.load('EVOLUTION_SERVER_URL', nil)

    if server_url.blank?
      return render json: { error: 'Evolution server URL not configured' }, status: :unprocessable_entity
    end

    render json: { server_url: server_url }
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:id])
    authorize @inbox, :show?
  end

  def fetch_agent_bot
    @agent_bot = AgentBot.find(params[:agent_bot]) if params[:agent_bot]
  end

  def validate_whatsapp_cloud_channel
    return if @inbox.channel.is_a?(Channel::Whatsapp) && @inbox.channel.provider == 'whatsapp_cloud'

    render json: { error: 'Health data only available for WhatsApp Cloud API channels' }, status: :bad_request
  end

  def create_channel
    return unless allowed_channel_types.include?(permitted_params[:channel][:type])

    account_channels_method.create!(permitted_params(channel_type_from_params::EDITABLE_ATTRS)[:channel].except(:type))
  end

  def allowed_channel_types
    %w[web_widget api email line telegram whatsapp sms]
  end

  def update_inbox_working_hours
    @inbox.update_working_hours(params.permit(working_hours: Inbox::OFFISABLE_ATTRS)[:working_hours]) if params[:working_hours]
  end

  def update_channel
    channel_attributes = get_channel_attributes(@inbox.channel_type)
    return if permitted_params(channel_attributes)[:channel].blank?

    validate_and_update_email_channel(channel_attributes) if @inbox.inbox_type == 'Email'

    reauthorize_and_update_channel(channel_attributes)
    update_channel_feature_flags
  end

  def channel_update_required?
    permitted_params(get_channel_attributes(@inbox.channel_type))[:channel].present?
  end

  def validate_and_update_email_channel(channel_attributes)
    validate_email_channel(channel_attributes)
  rescue StandardError => e
    render json: { message: e }, status: :unprocessable_entity and return
  end

  def reauthorize_and_update_channel(channel_attributes)
    @inbox.channel.reauthorized! if @inbox.channel.respond_to?(:reauthorized!)
    @inbox.channel.update!(permitted_params(channel_attributes)[:channel])
  end

  def update_channel_feature_flags
    return unless @inbox.web_widget?
    return unless permitted_params(Channel::WebWidget::EDITABLE_ATTRS)[:channel].key? :selected_feature_flags

    @inbox.channel.selected_feature_flags = permitted_params(Channel::WebWidget::EDITABLE_ATTRS)[:channel][:selected_feature_flags]
    @inbox.channel.save!
  end

  def format_csat_config(config)
    formatted = {
      'display_type' => config['display_type'] || 'emoji',
      'message' => config['message'] || '',
      :survey_rules => {
        'operator' => config.dig('survey_rules', 'operator') || 'contains',
        'values' => config.dig('survey_rules', 'values') || []
      },
      'button_text' => config['button_text'] || 'Please rate us',
      'language' => config['language'] || 'en'
    }
    format_template_config(config, formatted)
    formatted
  end

  def format_template_config(config, formatted)
    formatted['template'] = config['template'] if config['template'].present?
  end

  def inbox_attributes
    [:name, :avatar, :greeting_enabled, :greeting_message, :enable_email_collect, :csat_survey_enabled,
     :enable_auto_assignment, :working_hours_enabled, :out_of_office_message, :timezone, :allow_messages_after_resolved,
     :lock_to_single_conversation, :portal_id, :sender_name_type, :business_name,
     { csat_config: [:display_type, :message, :button_text, :language,
                     { survey_rules: [:operator, { values: [] }],
                       template: [:name, :template_id, :friendly_name, :content_sid, :approval_sid, :created_at, :language, :status] }] }]
  end

  def permitted_params(channel_attributes = [])
    # We will remove this line after fixing https://linear.app/chatwoot/issue/CW-1567/null-value-passed-as-null-string-to-backend
    params.each { |k, v| params[k] = params[k] == 'null' ? nil : v }
    params.permit(*inbox_attributes, channel: [:type, *channel_attributes])
  end

  def channel_type_from_params
    {
      'web_widget' => Channel::WebWidget,
      'api' => Channel::Api,
      'email' => Channel::Email,
      'line' => Channel::Line,
      'telegram' => Channel::Telegram,
      'whatsapp' => Channel::Whatsapp,
      'sms' => Channel::Sms
    }[permitted_params[:channel][:type]]
  end

  def get_channel_attributes(channel_type)
    channel_type.constantize.const_defined?(:EDITABLE_ATTRS) ? channel_type.constantize::EDITABLE_ATTRS.presence : []
  end

  def whatsapp_channel?
    @inbox.whatsapp? || (@inbox.twilio? && @inbox.channel.whatsapp?)
  end

  def trigger_template_sync
    if @inbox.whatsapp?
      Channels::Whatsapp::TemplatesSyncJob.perform_later(@inbox.channel)
    elsif @inbox.twilio? && @inbox.channel.whatsapp?
      Channels::Twilio::TemplatesSyncJob.perform_later(@inbox.channel)
    end
  end
end

Api::V1::Accounts::InboxesController.prepend_mod_with('Api::V1::Accounts::InboxesController')
