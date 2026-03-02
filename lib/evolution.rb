require 'net/http'
require 'uri'
require 'json'

class Evolution
  def self.fetch_instance(server_url, instance, api_key)
    uri = URI("#{server_url}/instance/fetch/#{instance}")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Get.new(uri)
    request['apikey'] = api_key

    response = http.request(request)
    
    {
      code: response.code.to_i,
      body: response.body,
      exists: response.is_a?(Net::HTTPSuccess)
    }
  rescue URI::InvalidURIError => e
    Rails.logger.error("Evolution API error (fetch_instance): Invalid URI - #{e.message}")
    {
      code: 0,
      body: '',
      exists: false,
      error: "Invalid server URL: #{e.message}"
    }
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Evolution API error (fetch_instance): Timeout - #{e.message}")
    {
      code: 0,
      body: '',
      exists: false,
      error: "Connection timeout: #{e.message}"
    }
  rescue StandardError => e
    Rails.logger.error("Evolution API error (fetch_instance): #{e.class} - #{e.message}")
    {
      code: 0,
      body: '',
      exists: false,
      error: "Connection error: #{e.message}"
    }
  end

  def self.create_instance(server_url, instance_name, api_key, options = {})
    uri = URI("#{server_url}/instance/create")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request['apikey'] = api_key
    request['Content-Type'] = 'application/json'
    
    payload = {
      instanceName: instance_name,
      qrcode: options.fetch(:qrcode, true),
      integration: options.fetch(:integration, 'WHATSAPP-BAILEYS'),
      rejectCall: options.fetch(:reject_call, true),
      groupsIgnore: options.fetch(:groups_ignore, true),
      alwaysOnline: options.fetch(:always_online, true),
      readMessages: options.fetch(:read_messages, true),
      readStatus: options.fetch(:read_status, true),
      syncFullHistory: options.fetch(:sync_full_history, true)
    }
    
    # Optional fields
    payload[:token] = options[:token] if options[:token].present?
    payload[:number] = options[:number] if options[:number].present?
    payload[:msgCall] = options[:msg_call] if options[:msg_call].present?
    payload[:proxyHost] = options[:proxy_host] if options[:proxy_host].present?
    payload[:proxyPort] = options[:proxy_port] if options[:proxy_port].present?
    payload[:proxyProtocol] = options[:proxy_protocol] if options[:proxy_protocol].present?
    payload[:proxyUsername] = options[:proxy_username] if options[:proxy_username].present?
    payload[:proxyPassword] = options[:proxy_password] if options[:proxy_password].present?
    
    # Webhook configuration
    if options[:webhook].present?
      payload[:webhook] = {
        url: options[:webhook][:url],
        byEvents: options[:webhook].fetch(:by_events, true),
        base64: options[:webhook].fetch(:base64, true),
        events: options[:webhook][:events] || ['APPLICATION_STARTUP']
      }
      payload[:webhook][:headers] = options[:webhook][:headers] if options[:webhook][:headers].present?
    end
    
    # RabbitMQ configuration
    if options[:rabbitmq].present?
      payload[:rabbitmq] = {
        enabled: options[:rabbitmq].fetch(:enabled, true),
        events: options[:rabbitmq][:events] || ['APPLICATION_STARTUP']
      }
    end
    
    # SQS configuration
    if options[:sqs].present?
      payload[:sqs] = {
        enabled: options[:sqs].fetch(:enabled, true),
        events: options[:sqs][:events] || ['APPLICATION_STARTUP']
      }
    end
    
    # Chatwoot integration
    if options[:chatwoot].present?
      payload[:chatwootAccountId] = options[:chatwoot][:account_id] if options[:chatwoot][:account_id].present?
      payload[:chatwootToken] = options[:chatwoot][:token] if options[:chatwoot][:token].present?
      payload[:chatwootUrl] = options[:chatwoot][:url] if options[:chatwoot][:url].present?
      payload[:chatwootSignMsg] = options[:chatwoot].fetch(:sign_msg, true)
      payload[:chatwootReopenConversation] = options[:chatwoot].fetch(:reopen_conversation, true)
      payload[:chatwootConversationPending] = options[:chatwoot].fetch(:conversation_pending, true)
      payload[:chatwootImportContacts] = options[:chatwoot].fetch(:import_contacts, true)
      payload[:chatwootNameInbox] = options[:chatwoot][:name_inbox] if options[:chatwoot][:name_inbox].present?
      payload[:chatwootMergeBrazilContacts] = options[:chatwoot].fetch(:merge_brazil_contacts, true)
      payload[:chatwootImportMessages] = options[:chatwoot].fetch(:import_messages, true)
      payload[:chatwootDaysLimitImportMessages] = options[:chatwoot][:days_limit_import_messages] if options[:chatwoot][:days_limit_import_messages].present?
      payload[:chatwootOrganization] = options[:chatwoot][:organization] if options[:chatwoot][:organization].present?
      payload[:chatwootLogo] = options[:chatwoot][:logo] if options[:chatwoot][:logo].present?
    end
    
    request.body = payload.to_json

    response = http.request(request)
    
    error_message = nil
    unless response.is_a?(Net::HTTPSuccess)
      begin
        error_body = JSON.parse(response.body) if response.body.present?
        error_message = error_body['message'] || error_body['error'] || response.body if error_body.is_a?(Hash)
      rescue JSON::ParserError
        error_message = response.body.presence
      end
      error_message ||= "HTTP #{response.code}: #{response.message}"
    end
    
    result = {
      code: response.code.to_i,
      body: response.body,
      success: response.is_a?(Net::HTTPSuccess),
      error: error_message
    }
    
    # Setup Chatwoot integration automatically after successful instance creation
    if result[:success] && options[:chatwoot].present?
      chatwoot_result = setup_chatwoot_integration(
        server_url,
        instance_name,
        api_key,
        options[:chatwoot]
      )
      result[:chatwoot_setup] = chatwoot_result
    end
    
    result
  rescue URI::InvalidURIError => e
    Rails.logger.error("Evolution API error (create_instance): Invalid URI - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Invalid server URL: #{e.message}"
    }
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Evolution API error (create_instance): Timeout - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Connection timeout: #{e.message}"
    }
  rescue StandardError => e
    Rails.logger.error("Evolution API error (create_instance): #{e.class} - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Connection error: #{e.message}"
    }
  end

  def self.setup_chatwoot_integration(server_url, instance, api_key, chatwoot_options)
    uri = URI("#{server_url}/chatwoot/set/#{instance}")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request['apikey'] = api_key
    request['Content-Type'] = 'application/json'
    
    payload = {
      enabled: chatwoot_options.fetch(:enabled, true),
      accountId: chatwoot_options[:account_id],
      token: chatwoot_options[:token],
      url: chatwoot_options[:url],
      signMsg: chatwoot_options.fetch(:sign_msg, true),
      reopenConversation: chatwoot_options.fetch(:reopen_conversation, true),
      conversationPending: chatwoot_options.fetch(:conversation_pending, true),
      nameInbox: chatwoot_options[:name_inbox],
      mergeBrazilContacts: chatwoot_options.fetch(:merge_brazil_contacts, true),
      importContacts: chatwoot_options.fetch(:import_contacts, true),
      importMessages: chatwoot_options.fetch(:import_messages, true),
      daysLimitImportMessages: chatwoot_options[:days_limit_import_messages] || 0,
      signDelimiter: chatwoot_options[:sign_delimiter] || "\n",
      autoCreate: chatwoot_options.fetch(:auto_create, true),
      organization: chatwoot_options[:organization] || '',
      logo: chatwoot_options[:logo] || '',
      ignoreJids: chatwoot_options[:ignore_jids] || []
    }
    
    request.body = payload.to_json

    response = http.request(request)
    
    error_message = nil
    unless response.is_a?(Net::HTTPSuccess)
      begin
        error_body = JSON.parse(response.body) if response.body.present?
        error_message = error_body['message'] || error_body['error'] || response.body if error_body.is_a?(Hash)
      rescue JSON::ParserError
        error_message = response.body.presence
      end
      error_message ||= "HTTP #{response.code}: #{response.message}"
    end
    
    {
      code: response.code.to_i,
      body: response.body,
      success: response.is_a?(Net::HTTPSuccess),
      error: error_message
    }
  rescue URI::InvalidURIError => e
    Rails.logger.error("Evolution API error (setup_chatwoot_integration): Invalid URI - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Invalid server URL: #{e.message}"
    }
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Evolution API error (setup_chatwoot_integration): Timeout - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Connection timeout: #{e.message}"
    }
  rescue StandardError => e
    Rails.logger.error("Evolution API error (setup_chatwoot_integration): #{e.class} - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Connection error: #{e.message}"
    }
  end

  def self.connect_instance(server_url, instance, api_key)
    uri = URI("#{server_url}/instance/connect/#{instance}")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Get.new(uri)
    request['apikey'] = api_key

    response = http.request(request)
    
    error_message = nil
    unless response.is_a?(Net::HTTPSuccess)
      begin
        error_body = JSON.parse(response.body) if response.body.present?
        error_message = error_body['message'] || error_body['error'] || response.body if error_body.is_a?(Hash)
      rescue JSON::ParserError
        error_message = response.body.presence
      end
      error_message ||= "HTTP #{response.code}: #{response.message}"
    end
    
    {
      code: response.code.to_i,
      body: response.body,
      success: response.is_a?(Net::HTTPSuccess),
      error: error_message
    }
  rescue URI::InvalidURIError => e
    Rails.logger.error("Evolution API error: Invalid URI - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Invalid server URL: #{e.message}"
    }
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Evolution API error: Timeout - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Connection timeout: #{e.message}"
    }
  rescue StandardError => e
    Rails.logger.error("Evolution API error: #{e.class} - #{e.message}")
    Rails.logger.error("Evolution API backtrace: #{e.backtrace.first(3).join("\n")}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Connection error: #{e.message}"
    }
  end

  def self.restart_instance(server_url, instance, api_key)
    uri = URI("#{server_url}/instance/restart/#{instance}")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Put.new(uri)
    request['apikey'] = api_key

    response = http.request(request)
    
    error_message = nil
    unless response.is_a?(Net::HTTPSuccess)
      begin
        error_body = JSON.parse(response.body) if response.body.present?
        error_message = error_body['message'] || error_body['error'] || response.body if error_body.is_a?(Hash)
      rescue JSON::ParserError
        error_message = response.body.presence
      end
      error_message ||= "HTTP #{response.code}: #{response.message}"
    end
    
    {
      code: response.code.to_i,
      body: response.body,
      success: response.is_a?(Net::HTTPSuccess),
      error: error_message
    }
  rescue URI::InvalidURIError => e
    Rails.logger.error("Evolution API error (restart_instance): Invalid URI - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Invalid server URL: #{e.message}"
    }
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Evolution API error (restart_instance): Timeout - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Connection timeout: #{e.message}"
    }
  rescue StandardError => e
    Rails.logger.error("Evolution API error (restart_instance): #{e.class} - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Connection error: #{e.message}"
    }
  end

  def self.connection_state(server_url, instance, api_key)
    uri = URI("#{server_url}/instance/connectionState/#{instance}")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Get.new(uri)
    request['apikey'] = api_key

    response = http.request(request)
    
    error_message = nil
    unless response.is_a?(Net::HTTPSuccess)
      begin
        error_body = JSON.parse(response.body) if response.body.present?
        error_message = error_body['message'] || error_body['error'] || response.body if error_body.is_a?(Hash)
      rescue JSON::ParserError
        error_message = response.body.presence
      end
      error_message ||= "HTTP #{response.code}: #{response.message}"
    end
    
    {
      code: response.code.to_i,
      body: response.body,
      success: response.is_a?(Net::HTTPSuccess),
      error: error_message
    }
  rescue URI::InvalidURIError => e
    Rails.logger.error("Evolution API error (connection_state): Invalid URI - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Invalid server URL: #{e.message}"
    }
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Evolution API error (connection_state): Timeout - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Connection timeout: #{e.message}"
    }
  rescue StandardError => e
    Rails.logger.error("Evolution API error (connection_state): #{e.class} - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Connection error: #{e.message}"
    }
  end

  def self.logout_instance(server_url, instance, api_key)
    uri = URI("#{server_url}/instance/logout/#{instance}")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Delete.new(uri)
    request['apikey'] = api_key

    response = http.request(request)
    
    error_message = nil
    unless response.is_a?(Net::HTTPSuccess)
      begin
        error_body = JSON.parse(response.body) if response.body.present?
        error_message = error_body['message'] || error_body['error'] || response.body if error_body.is_a?(Hash)
      rescue JSON::ParserError
        error_message = response.body.presence
      end
      error_message ||= "HTTP #{response.code}: #{response.message}"
    end
    
    {
      code: response.code.to_i,
      body: response.body,
      success: response.is_a?(Net::HTTPSuccess),
      error: error_message
    }
  rescue URI::InvalidURIError => e
    Rails.logger.error("Evolution API error (logout_instance): Invalid URI - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Invalid server URL: #{e.message}"
    }
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Evolution API error (logout_instance): Timeout - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Connection timeout: #{e.message}"
    }
  rescue StandardError => e
    Rails.logger.error("Evolution API error (logout_instance): #{e.class} - #{e.message}")
    {
      code: 0,
      body: '',
      success: false,
      error: "Connection error: #{e.message}"
    }
  end
end
