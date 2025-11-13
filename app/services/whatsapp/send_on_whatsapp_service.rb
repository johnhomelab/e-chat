class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  include BaileysHelper

  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    should_send_template_message = template_params.present? || !message.conversation.can_reply?
    if should_send_template_message
      send_template_message
    elsif channel.provider == 'baileys'
      send_baileys_session_message
    else
      send_session_message
    end
  end

  def send_template_message
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params,
      message: message
    )

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      message.update!(status: :failed, external_error: 'Template not found or invalid template name')
      return
    end

    message_id = channel.send_template(recipient_id, {
                                         name: name,
                                         namespace: namespace,
                                         lang_code: lang_code,
                                         parameters: processed_parameters
                                       }, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def send_baileys_session_message
    with_baileys_channel_lock_on_outgoing_message(channel.id) { send_session_message }
  end

  def send_session_message
    message_id = channel.send_message(recipient_id, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def recipient_id
    return message.conversation.contact_inbox.source_id unless %w[baileys zapi].include?(channel.provider)

    # NOTE: `identifier` must be in the WhatsApp LID format
    message.conversation.contact.phone_number&.gsub(/[^\d]/, '') || message.conversation.contact.identifier
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end
end
