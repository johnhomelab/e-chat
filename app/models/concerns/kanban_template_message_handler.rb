module KanbanTemplateMessageHandler
  extend ActiveSupport::Concern

  private

  def handle_template_message_on_stage_change
    return unless saved_change_to_funnel_stage?
    return unless conversation.present?
    return unless account.kanban_config&.get_config_value('quick_message_enabled') == true

    new_stage = funnel_stage
    template = find_applicable_template(new_stage)

    return unless template

    send_template_message(template)
  end

  private

  def find_applicable_template(stage_id)
    return nil unless funnel&.stages&.dig(stage_id, 'message_templates')

    templates = funnel.stages[stage_id]['message_templates']

    # Primeiro, procurar por template padrão
    default_template = templates.find { |t| t['is_default'] && template_conditions_met?(t) }
    return default_template if default_template

    # Depois, procurar por qualquer template que atenda às condições
    templates.find { |t| template_conditions_met?(t) }
  end

  def template_conditions_met?(template)
    return true unless template['conditions']&.dig('enabled')
    return true unless template['conditions']['rules']&.any?

    template['conditions']['rules'].all? do |rule|
      check_condition_rule(rule)
    end
  end

  def check_condition_rule(rule)
    field_value = get_field_value(rule['field'])
    expected_value = rule['value']

    case rule['operator']
    when 'equals'
      normalize_value(field_value) == normalize_value(expected_value)
    when 'not_equals'
      normalize_value(field_value) != normalize_value(expected_value)
    when 'contains'
      normalize_value(field_value).include?(normalize_value(expected_value))
    when 'greater_than'
      field_value.to_f > expected_value.to_f
    when 'less_than'
      field_value.to_f < expected_value.to_f
    else
      false
    end
  end

  def get_field_value(field_path)
    field_path.split('.').reduce(self) do |obj, key|
      if key == 'priority'
        translate_priority(obj.item_details&.dig(key))
      else
        obj.item_details&.dig(key)
      end
    end
  end

  def normalize_value(value)
    value.to_s.downcase.strip
  end

  def send_template_message(template)
    message = conversation.messages.create!(
      account_id: account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content: template['content'],
      content_type: :text,
      private: false
    )

    Rails.logger.info "Template de mensagem enviado: #{template['title']} para conversa #{conversation.display_id}"
    message
  rescue StandardError => e
    Rails.logger.error "Erro ao enviar template de mensagem: #{e.message}"
    nil
  end

  def translate_priority(priority)
    case priority
    when 'none' then 'Nenhuma'
    when 'low' then 'Baixa'
    when 'medium' then 'Média'
    when 'high' then 'Alta'
    when 'urgent' then 'Urgente'
    else priority
    end
  end
end
