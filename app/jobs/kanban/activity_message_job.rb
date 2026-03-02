class Kanban::ActivityMessageJob < ApplicationJob
  queue_as :high

  def perform(kanban_item, activity_params)
    Rails.logger.info "Iniciando Kanban::ActivityMessageJob para item #{kanban_item.id}"
    return unless kanban_item

    # Garante que temos um array de atividades
    current_activities = kanban_item.activities || []
    
    # Cria a nova atividade com o usuário dos detalhes ou o usuário atual
    new_activity = {
      id: Time.current.to_i,
      type: activity_params[:type],
      details: activity_params[:details],
      created_at: Time.current.iso8601,
      user: activity_params[:details][:user] || {
        id: Current.user&.id,
        name: Current.user&.name,
        avatar_url: Current.user&.avatar_url
      }
    }

    Rails.logger.info "Registrando atividade: #{new_activity.inspect}"

    # Adiciona a nova atividade ao array
    activities = current_activities + [new_activity]

    # Atualiza o item do kanban com a nova atividade
    kanban_item.update!(activities: activities)

    # Se houver uma conversa vinculada, registra a atividade também na conversa
    if kanban_item.conversation.present?
      Rails.logger.info "Registrando atividade na conversa #{kanban_item.conversation.display_id}"
      content = generate_conversation_activity_content(activity_params, new_activity[:user])
      ::Conversations::ActivityMessageJob.perform_later(
        kanban_item.conversation,
        {
          account_id: kanban_item.account_id,
          inbox_id: kanban_item.conversation.inbox_id,
          message_type: :activity,
          content: content
        }
      )
    end
  rescue StandardError => e
    Rails.logger.error "Erro no Kanban::ActivityMessageJob: #{e.message}\n#{e.backtrace.join("\n")}"
    raise e
  end

  private

  def generate_conversation_activity_content(activity_params, user)
    user_name = user[:name] || 'Sistema'
    
    case activity_params[:type]
    when 'stage_changed'
      "#{user_name} moveu o item do Kanban para #{activity_params[:details][:new_stage]}"
    when 'priority_changed'
      "#{user_name} alterou a prioridade do item do Kanban para #{activity_params[:details][:new_priority]}"
    when 'agent_changed'
      "#{user_name} atribuiu o item do Kanban para #{activity_params[:details][:new_agent]}"
    when 'agent_assigned'
      "#{user_name} atribuiu o agente #{activity_params[:details][:agent_name]} ao item do Kanban"
    when 'agent_removed'
      "#{user_name} removeu o agente #{activity_params[:details][:agent_name]} do item do Kanban"
    when 'value_changed'
      "#{user_name} alterou o valor do item do Kanban"
    when 'status_changed'
      "#{user_name} alterou o status do item do Kanban para #{activity_params[:details][:new_status]}"
    when 'title_changed'
      "#{user_name} alterou o título do item do Kanban"
    when 'description_changed'
      "#{user_name} alterou a descrição do item do Kanban"
    when 'deadline_changed'
      "#{user_name} alterou o prazo do item do Kanban"
    when 'timer_started'
      "#{user_name} iniciou o timer do item do Kanban"
    when 'timer_stopped'
      "#{user_name} parou o timer do item do Kanban"
    when 'note_added'
      "#{user_name} adicionou uma nota ao item do Kanban: #{activity_params[:details][:note_text]}"
    when 'note_updated'
      "#{user_name} atualizou uma nota do item do Kanban"
    when 'note_removed'
      "#{user_name} removeu uma nota do item do Kanban: #{activity_params[:details][:note_text]}"
    when 'attachment_added'
      "#{user_name} adicionou um anexo ao item do Kanban: #{activity_params[:details][:filename]}"
    when 'attachment_removed'
      "#{user_name} removeu um anexo do item do Kanban: #{activity_params[:details][:filename]}"
    when 'checklist_item_added'
      "#{user_name} adicionou um item ao checklist: #{activity_params[:details][:item_text]}"
    when 'checklist_item_toggled'
      status = activity_params[:details][:completed] ? 'marcou como completo' : 'desmarcou'
      "#{user_name} #{status} um item do checklist: #{activity_params[:details][:item_text]}"
    when 'checklist_item_removed'
      "#{user_name} removeu um item do checklist: #{activity_params[:details][:item_text]}"
    when 'checklist_item_updated'
      "#{user_name} atualizou um item do checklist"
    when 'item_created'
      "#{user_name} criou o item do Kanban: #{activity_params[:details][:title]}"
    when 'custom_attribute_changed'
      "#{user_name} alterou o atributo #{activity_params[:details][:attribute_name]} do item do Kanban"
    when 'automated_action_executed'
      "#{user_name} executou uma ação automatizada (#{activity_params[:details][:action_type]}) no item do Kanban"
    when 'conversation_linked'
      "#{user_name} vinculou o item do Kanban à conversa"
    when 'conversation_unlinked'
      "#{user_name} desvinculou o item do Kanban da conversa"
    else
      "#{user_name} atualizou o item do Kanban"
    end
  end
end 