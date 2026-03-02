# == Schema Information
#
# Table name: kanban_items
#
#  id                      :bigint           not null, primary key
#  activities              :jsonb
#  assigned_agents         :jsonb
#  checklist               :jsonb
#  custom_attributes       :jsonb
#  funnel_stage            :string           not null
#  item_details            :jsonb
#  position                :integer          not null
#  stage_entered_at        :datetime
#  timer_duration          :integer          default(0)
#  timer_started_at        :datetime
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  conversation_display_id :bigint
#  funnel_id               :bigint           not null
#
# Indexes
#
#  index_kanban_items_on_account_id                                 (account_id)
#  index_kanban_items_on_account_id_and_funnel_id_and_funnel_stage  (account_id,funnel_id,funnel_stage)
#  index_kanban_items_on_activities                                 (activities) USING gin
#  index_kanban_items_on_assigned_agents                            (assigned_agents) USING gin
#  index_kanban_items_on_checklist                                  (checklist) USING gin
#  index_kanban_items_on_conversation_display_id                    (conversation_display_id)
#  index_kanban_items_on_funnel_id                                  (funnel_id)
#  index_kanban_items_on_funnel_id_and_funnel_stage                 (funnel_id,funnel_stage)
#  index_kanban_items_on_item_details                               (item_details) USING gin
#
# Foreign Keys
#
#  fk_rails_...  (funnel_id => funnels.id)
#

class KanbanItem < ApplicationRecord
  include Events::Types
  include KanbanActivityHandler
  include KanbanTemplateMessageHandler

  belongs_to :account
  belongs_to :conversation, lambda { |kanban_item|
    where(account_id: kanban_item.account_id)
  }, foreign_key: :conversation_display_id, primary_key: :display_id, class_name: 'Conversation', optional: true
  belongs_to :funnel

  validates :account_id, presence: true
  validates :funnel_id, presence: true
  validates :funnel_stage, presence: true
  validates :position, presence: true
  validates :item_details, presence: true

  validate :validate_item_details_title
  validate :validate_assigned_agents

  scope :order_by_position, -> { order(position: :asc) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :for_funnel, lambda { |funnel_id|
    funnel_id.present? ? where(funnel_id: funnel_id) : all
  }
  scope :in_stage, ->(stage) { where(funnel_stage: stage) }

  # Scope para buscar itens por agente
  scope :assigned_to_agent, lambda { |agent_id|
    where(
      "EXISTS (
      SELECT 1
      FROM jsonb_array_elements(kanban_items.assigned_agents) AS agent
      WHERE (agent->>'id')::int = ?
    )",
      agent_id.to_i
    )
  }

  scope :latest_only, -> { order(created_at: :desc).limit(1) }
  before_save :update_stage_entered_at, if: :funnel_stage_changed?
  before_create :set_stage_entered_at
  before_create :initialize_checklist_from_stage_templates
  after_commit :handle_activity_changes, on: [:create, :update]
  after_commit :handle_conversation_linked, on: [:create, :update]
  after_commit :handle_status_automation, on: [:update]
  after_commit :handle_item_creation_activity, on: [:create]
  after_commit :handle_checklist_changes, on: [:update]
  after_commit :handle_custom_attributes_changes, on: [:update]
  after_commit :invalidate_cache, on: [:create, :update, :destroy]

  has_many_attached :note_attachments
  has_many_attached :attachments

  validate :validate_attachments

  # Métodos para gerenciar agentes atribuídos
  def assign_agent(agent_id, assigned_by = nil)
    return false unless agent_id.present?

    agent = User.find_by(id: agent_id)
    return false unless agent

    # Verificar se o agente já está atribuído
    return false if agent_assigned?(agent_id)

    # Adicionar o agente à lista
    current_agents = assigned_agents || []
    current_agents << {
      id: agent.id,
      name: agent.name,
      email: agent.email,
      avatar_url: agent.avatar_url,
      assigned_at: Time.current,
      assigned_by: assigned_by&.id || Current.user&.id
    }

    self.assigned_agents = current_agents
    if save
      handle_agent_assigned(agent.id, agent.name)
      true
    else
      false
    end
  end

  def remove_agent(agent_id)
    return false unless agent_id.present?

    current_agents = assigned_agents || []
    filtered_agents = current_agents.reject do |agent|
      if agent.is_a?(Hash)
        agent['id'] == agent_id.to_i
      elsif agent.is_a?(Integer) || agent.is_a?(String)
        agent.to_i == agent_id.to_i
      else
        false
      end
    end

    if filtered_agents.length == current_agents.length
      false
    else
      # Encontrar o nome do agente que está sendo removido
      agent_to_remove = current_agents.find do |agent|
        if agent.is_a?(Hash)
          agent['id'] == agent_id.to_i
        elsif agent.is_a?(Integer) || agent.is_a?(String)
          agent.to_i == agent_id.to_i
        else
          false
        end
      end

      agent_name = if agent_to_remove.is_a?(Hash)
                     agent_to_remove['name']
                   elsif agent_to_remove.is_a?(Integer) || agent_to_remove.is_a?(String)
                     User.find_by(id: agent_to_remove.to_i)&.name
                   end

      self.assigned_agents = filtered_agents
      if save
        handle_agent_removed(agent_id, agent_name)
        true
      else
        false
      end
    end
  end

  def agent_assigned?(agent_id)
    return false unless assigned_agents.present?

    assigned_agents.any? do |agent|
      if agent.is_a?(Hash)
        agent['id'] == agent_id.to_i
      elsif agent.is_a?(Integer) || agent.is_a?(String)
        agent.to_i == agent_id.to_i
      else
        false
      end
    end
  end

  def primary_agent
    return nil unless assigned_agents.present? && assigned_agents.any?

    # Retorna o primeiro agente como principal
    agent_data = assigned_agents.first
    if agent_data.is_a?(Hash)
      User.find_by(id: agent_data['id']) if agent_data
    elsif agent_data.is_a?(Integer) || agent_data.is_a?(String)
      User.find_by(id: agent_data.to_i)
    else
      nil
    end
  end

  def assigned_agent_ids
    return [] unless assigned_agents.present?

    assigned_agents.map do |agent|
      if agent.is_a?(Hash)
        agent['id']
      elsif agent.is_a?(Integer) || agent.is_a?(String)
        agent.to_i
      else
        nil
      end
    end.compact
  end

  def assigned_agents_data
    return [] unless assigned_agents.present?

    assigned_agents.map do |agent_data|
      if agent_data.is_a?(Hash)
        {
          id: agent_data['id'],
          name: agent_data['name'],
          email: agent_data['email'],
          avatar_url: agent_data['avatar_url'],
          assigned_at: agent_data['assigned_at'],
          assigned_by: agent_data['assigned_by']
        }
      elsif agent_data.is_a?(Integer) || agent_data.is_a?(String)
        agent_id = agent_data.to_i
        agent = User.find_by(id: agent_id)
        if agent
          {
            id: agent.id,
            name: agent.name,
            email: agent.email,
            avatar_url: agent.avatar_url,
            assigned_at: Time.current,
            assigned_by: Current.user&.id
          }
        else
          nil
        end
      else
        nil
      end
    end.compact
  end

  # Método de compatibilidade para manter funcionalidade existente
  def agent
    primary_agent
  end

  def move_to_stage(new_stage, stage_entered_at = nil)
    return if new_stage == funnel_stage

    # Adicionar checklists da nova etapa antes de mover
    checklist_items_added = add_checklist_templates_from_stage(new_stage)

    update(
      funnel_stage: new_stage,
      stage_entered_at: stage_entered_at || Time.current,
      checklist: checklist  # Incluir checklist explicitamente para garantir que seja salvo
    )

    # Registrar atividade para cada item de checklist adicionado automaticamente
    if checklist_items_added && checklist_items_added.any?
      checklist_items_added.each do |item|
        handle_checklist_item_added(item['text']) if item['text'].present?
      end
    end
  end

  def start_timer
    return if timer_started_at.present?

    update(timer_started_at: Time.current)
    handle_timer_started if saved_change_to_timer_started_at?
  end

  def stop_timer
    return unless timer_started_at.present?

    elapsed_time = Time.current - timer_started_at
    update(
      timer_started_at: nil,
      timer_duration: timer_duration + elapsed_time.to_i
    )
    handle_timer_stopped if saved_change_to_timer_started_at?
  end

  def time_in_current_stage
    return 0 unless stage_entered_at

    (Time.current - stage_entered_at).to_i
  end

  def self.debug_counts
    Rails.logger.info '=== KanbanItem Debug Counts ==='
    Rails.logger.info "Total items: #{count}"
    Rails.logger.info "Items by funnel: #{group(:funnel_id).count}"
    Rails.logger.info "Items by stage: #{group(:funnel_stage).count}"
  end

  def validate_note_attachment(attachment)
    return false unless attachment

    if attachment.blob.byte_size > 40.megabytes
      errors.add(:note_attachments, 'size must be less than 40MB')
      return false
    end

    content_type = attachment.blob.content_type
    unless content_type.in?(%w[image/png image/jpg image/jpeg application/pdf])
      errors.add(:note_attachments, 'must be an image (png, jpg) or PDF')
      return false
    end
    true
  end

  def serialized_attachments
    return [] unless attachments.attached?

    attachments.map do |attachment|
      {
        id: attachment.id,
        url: Rails.application.routes.url_helpers.rails_blob_url(attachment, only_path: true),
        filename: attachment.filename.to_s,
        byte_size: attachment.byte_size,
        content_type: attachment.content_type,
        created_at: attachment.created_at,
        source: {
          type: 'item',
          id: id
        }
      }
    end
  end

  def attachments_count
    return { total_count: 0 } unless attachments.attached?

    { total_count: attachments.count }
  end

  def checklist_count
    return { total_count: 0, completed_count: 0 } unless checklist.present?

    checklist_array = checklist.is_a?(Array) ? checklist : []
    total_count = checklist_array.length
    completed_count = checklist_array.count { |item| item['completed'] == true }

    {
      total_count: total_count,
      completed_count: completed_count
    }
  end

  def all_required_checklist_items_completed?
    return true unless checklist.present?

    checklist_array = checklist.is_a?(Array) ? checklist : []
    
    # Filtra itens obrigatórios (pode ser true, 'true', ou qualquer valor truthy)
    required_items = checklist_array.select do |item| 
      item['required'].to_s == 'true' || item['required'] == true
    end
    
    # Se não há itens obrigatórios, retorna true
    return true if required_items.empty?
    
    # Verifica se todos os itens obrigatórios estão completos
    # Retorna false se algum item obrigatório não estiver completo
    required_items.all? do |item|
      item['completed'].to_s == 'true' || item['completed'] == true
    end
  end

  def notes_count
    notes_array = normalized_notes
    { total_count: notes_array.length }
  end

  # Método para garantir que notes seja sempre um Array
  def normalized_notes
    notes_data = item_details&.dig('notes')
    return [] unless notes_data.present?

    notes_data.is_a?(Array) ? notes_data : []
  end

  # Método para adicionar uma nota de forma segura
  def add_note(note_data)
    notes = normalized_notes
    notes << note_data.merge(id: SecureRandom.uuid, created_at: Time.current)
    self.item_details = item_details.merge('notes' => notes)
    if save!
      handle_note_added(note_data['text']) if note_data['text'].present?
    end
  end

  # Método para remover uma nota de forma segura
  def remove_note(note_id)
    notes = normalized_notes
    note_to_remove = notes.find { |note| note['id'] == note_id }
    filtered_notes = notes.reject { |note| note['id'] == note_id }
    self.item_details = item_details.merge('notes' => filtered_notes)
    if save!
      handle_note_removed(note_to_remove['text']) if note_to_remove && note_to_remove['text'].present?
    end
  end

  # Método para atualizar uma nota de forma segura
  def update_note(note_id, note_data)
    notes = normalized_notes
    note_index = notes.find_index { |note| note['id'] == note_id }

    return false unless note_index

    old_text = notes[note_index]['text']
    notes[note_index] = notes[note_index].merge(note_data).merge(updated_at: Time.current)
    self.item_details = item_details.merge('notes' => notes)
    if save!
      new_text = note_data['text']
      handle_note_updated(note_id, old_text, new_text) if new_text.present? && old_text != new_text
    end
  end

  # Método para remover um item do checklist de forma segura
  def remove_checklist_item(checklist_item_id)
    checklist_array = checklist.is_a?(Array) ? checklist : []
    item_to_remove = checklist_array.find { |item| item['id'] == checklist_item_id }
    filtered_checklist = checklist_array.reject { |item| item['id'] == checklist_item_id }
    self.checklist = filtered_checklist
    if save!
      handle_checklist_item_removed(item_to_remove['text']) if item_to_remove && item_to_remove['text'].present?
    end
  end

  # Método para atualizar um item do checklist de forma segura
  def update_checklist_item(checklist_item_id, checklist_data)
    checklist_array = checklist.is_a?(Array) ? checklist : []
    item_index = checklist_array.find_index { |item| item['id'] == checklist_item_id }

    return false unless item_index

    old_text = checklist_array[item_index]['text']
    checklist_array[item_index] = checklist_array[item_index].merge(checklist_data).merge(updated_at: Time.current)
    self.checklist = checklist_array
    if save!
      new_text = checklist_data['text']
      handle_checklist_item_updated(old_text, new_text) if new_text.present? && old_text != new_text
    end
  end

  def item_details_for_index
    return item_details unless item_details.present?

    # Criar uma cópia dos item_details mas substituir notes pela contagem e remover custom_attributes e offers
    item_details_dup = item_details.dup
    if item_details_dup['notes'].present?
      item_details_dup['notes'] = notes_count
    end
    # Remover custom_attributes e offers do index para reduzir payload
    item_details_dup.delete('custom_attributes')
    item_details_dup.delete('offers')
    item_details_dup
  end

  # Retorna os dados serializados do funnel associado
  def funnel_data
    return unless funnel

    {
      id: funnel.id,
      name: funnel.name,
      description: funnel.description,
      active: funnel.active,
      stages: funnel.stages
    }
  end

  # Retorna os dados serializados da conversation associada, se houver
  def conversation_data
    conv = conversation
    return unless conv

    # Buscar a última mensagem da conversa
    last_message = conv.messages
                      .includes(:sender)
                      .where.not(message_type: [:activity, :template])
                      .order(created_at: :desc)
                      .first

    {
      id: conv.id,
      display_id: conv.display_id,
      inbox_id: conv.inbox_id,
      account_id: conv.account_id,
      status: conv.status,
      priority: conv.priority,
      created_at: conv.created_at,
      updated_at: conv.updated_at,
      label_list: conv.try(:cached_label_list_array),
      assignee: (if conv.assignee.present?
                   {
                     id: conv.assignee.id,
                     name: conv.assignee.name,
                     email: conv.assignee.email,
                     avatar_url: conv.assignee.avatar_url,
                     availability_status: conv.assignee.availability_status
                   }
                 end),
      contact: (if conv.contact.present?
                  {
                    id: conv.contact.id,
                    name: conv.contact.name,
                    email: conv.contact.email,
                    phone_number: conv.contact.phone_number,
                    thumbnail: conv.contact.avatar_url
                  }
                end),
      inbox: (if conv.inbox.present?
                {
                  id: conv.inbox.id,
                  name: conv.inbox.name,
                  channel_type: conv.inbox.channel_type
                }
              end),
      last_message: (if last_message.present?
                      {
                        id: last_message.id,
                        content: last_message.content,
                        message_type: last_message.message_type,
                        created_at: last_message.created_at,
                        sender: (if last_message.sender.present?
                                  {
                                    id: last_message.sender.id,
                                    name: last_message.sender.name,
                                    email: last_message.sender.email,
                                    avatar_url: last_message.sender.avatar_url,
                                    type: last_message.sender_type
                                  }
                                end)
                      }
                    end)
    }
  end

  def as_json(options = {})
    # Excluir campos desnecessários para reduzir payload
    excluded_fields = %w[timer_started_at timer_duration position custom_attributes]
    base_data = super(options).except(*excluded_fields)

    # Para index e show, retornar apenas counts dos attachments, checklist e notes
    show_lightweight = options[:for_index] || options[:for_show]

    attachments_data = if show_lightweight
                         attachments_count
                       else
                         serialized_attachments
                       end

    checklist_data = if show_lightweight
                       checklist_count
                     else
                       checklist
                     end

    # Para index e show, modificar item_details para incluir apenas contagem de notes
    item_details_data = if show_lightweight
                          item_details_for_index
                        else
                          item_details
                        end

    base_data.merge(
      'assigned_agents' => assigned_agents_data,
      'funnel' => funnel_data,
      'conversation' => conversation_data,
      'attachments' => attachments_data,
      'checklist' => checklist_data,
      'item_details' => item_details_data,
      'activities' => activities || []
    )
  end

  def validate_attachments
    return unless attachments.attached?

    # Lista abrangente de tipos MIME aceitos, compatível com ALLOWED_FILE_TYPES do frontend
    allowed_content_types = [
      # Imagens
      /^image\//,
      # Áudio
      /^audio\//,
      # Vídeo
      /^video\//,
      # Arquivos de texto e documentos
      'text/csv', 'text/plain', 'application/json', 'application/pdf', 'text/rtf',
      'application/xml', 'text/xml',
      # Arquivos compactados
      'application/zip', 'application/x-7z-compressed', 'application/vnd.rar', 'application/x-tar',
      # Documentos Microsoft Office
      'application/msword', 'application/vnd.ms-excel', 'application/vnd.ms-powerpoint',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      # Documentos OpenDocument
      'application/vnd.oasis.opendocument.text',
      # Formato 3GPP
      'audio/3gpp'
    ]

    attachments.each do |attachment|
      # Verifica se o tipo MIME corresponde a algum padrão permitido
      is_allowed = allowed_content_types.any? do |allowed_type|
        if allowed_type.is_a?(Regexp)
          attachment.content_type.match?(allowed_type)
        else
          attachment.content_type == allowed_type
        end
      end

      unless is_allowed
        errors.add(:attachments, 'tipo de arquivo não permitido')
      end

      errors.add(:attachments, 'deve ter menos de 10MB') if attachment.byte_size > 10.megabytes
    end
  end

  def validate_item_details_title
    if item_details.is_a?(Hash)
      errors.add(:item_details, 'deve conter o campo title preenchido') if item_details['title'].blank?
    else
      errors.add(:item_details, 'deve ser um objeto com o campo title')
    end
  end

  def validate_assigned_agents
    return unless assigned_agents.present?

    unless assigned_agents.is_a?(Array)
      errors.add(:assigned_agents, 'deve ser um array')
      return
    end

    assigned_agents.each_with_index do |agent_data, index|
      unless agent_data.is_a?(Hash)
        errors.add(:assigned_agents, "agente na posição #{index} deve ser um objeto")
        next
      end

      errors.add(:assigned_agents, "agente na posição #{index} deve ter um ID") unless agent_data['id'].present?
    end
  end

  private

  def handle_activity_changes
    handle_stage_change
    handle_priority_change
    handle_agent_change
    handle_value_change
    handle_status_change
    handle_title_change
    handle_description_change
    handle_deadline_change
    handle_template_message_on_stage_change
  end

  def handle_status_automation
    # Só executar se houve mudança no status
    return unless saved_change_to_attribute?(:item_details) && item_details.present?

    old_details = item_details_before_last_save || {}
    new_details = item_details

    old_status = old_details.dig('status')
    new_status = new_details.dig('status')

    return if old_status == new_status || new_status.blank?

    # Buscar automações configuradas para este status
    automations = new_details.dig('automations') || []
    status_automations = automations.select do |automation|
      automation['trigger_type'] == 'status_change' &&
      automation['trigger_value'] == new_status &&
      automation['enabled'] != false
    end

    status_automations.each do |automation|
      execute_status_automation(automation)
    end
  rescue => e
    # Log error but don't break the save operation
    Rails.logger.error("Error executing status automation for item #{id}: #{e.message}")
  end

  def execute_status_automation(automation)
    action = automation['action']
    action_config = automation['action_config'] || {}

    case action
    when 'move_to_stage'
      move_to_stage_automation(action_config)
      handle_automated_action_executed('move_to_stage', { new_stage: action_config['stage'] })
    when 'assign_agent'
      assign_agent_automation(action_config)
      handle_automated_action_executed('assign_agent', { agent_id: action_config['agent_id'] })
    when 'create_note'
      create_note_automation(action_config)
      handle_automated_action_executed('create_note', { note_text: action_config['note_text']&.truncate(50) })
    when 'update_checklist'
      update_checklist_automation(action_config)
      handle_automated_action_executed('update_checklist', { checklist_updates: action_config['checklist_updates']&.size })
    when 'notify_team'
      notify_team_automation(action_config)
      handle_automated_action_executed('notify_team', { message: action_config['message']&.truncate(50) })
    end
  end

  def move_to_stage_automation(config)
    new_stage = config['stage']
    return unless new_stage.present?

    # Verificar se já está na etapa
    return if funnel_stage == new_stage

    # Verificar se todos os itens obrigatórios do checklist estão completos
    unless all_required_checklist_items_completed?
      Rails.logger.info("Cannot auto-move item #{id} to stage #{new_stage}: required checklist items not completed")
      return
    end

    move_to_stage(new_stage)
    save! if changed?
  end

  def assign_agent_automation(config)
    agent_id = config['agent_id']
    return unless agent_id.present?

    agent = User.find_by(id: agent_id)
    return unless agent

    # Só atribuir se não estiver já atribuído
    unless agent_assigned?(agent_id)
      assign_agent(agent_id, Current.user)
    end
  end

  def create_note_automation(config)
    note_text = config['note_text']
    return unless note_text.present?

    note_data = {
      text: note_text,
      author: 'Sistema',
      author_id: nil,
      attachments: [],
      linked_item_id: nil,
      linked_conversation_id: nil,
      linked_contact_id: nil
    }

    add_note(note_data)
  end

  def update_checklist_automation(config)
    checklist_updates = config['checklist_updates'] || []
    return if checklist_updates.empty?

    current_checklist = checklist || []

    checklist_updates.each do |update|
      item_id = update['checklist_item_id']
      completed = update['completed']
      text = update['text']

      checklist_item = current_checklist.find { |item| item['id'] == item_id }
      next unless checklist_item

      checklist_item['completed'] = completed if completed.present?
      checklist_item['text'] = text if text.present?
      checklist_item['updated_at'] = Time.current
    end

    self.checklist = current_checklist
    save! if changed?
  end

  def notify_team_automation(config)
    # Por enquanto só log, pode ser implementado depois com notificações reais
    message = config['message'] || "Item #{id} mudou para status #{item_details['status']}"
    Rails.logger.info("Team notification: #{message}")

    # TODO: Implementar notificações reais (email, slack, etc.)
  end

  def set_stage_entered_at
    self.stage_entered_at = Time.current
  end

  def update_stage_entered_at
    self.stage_entered_at = Time.current
  end

  def handle_item_creation_activity
    handle_item_created
  end

  def invalidate_cache
    # Invalida cache do item específico
    Rails.cache.delete("kanban_item:#{id}:#{updated_at.to_i}")

    # Invalida cache do item com timestamp anterior (se foi update)
    if updated_at_before_last_save.present?
      Rails.cache.delete("kanban_item:#{id}:#{updated_at_before_last_save.to_i}")
    end
  end

  def initialize_checklist_from_stage_templates
    # Retorna se já existe checklist definido
    return if checklist.present? && checklist.is_a?(Array) && checklist.any?
    
    # Retorna se não há funnel ou funnel_stage
    return unless funnel.present? && funnel_stage.present?
    
    # Busca os templates da etapa atual
    stage_data = funnel.stages&.dig(funnel_stage)
    return unless stage_data.present?
    
    templates = stage_data['checklist_templates']
    return unless templates.present? && templates.is_a?(Array) && templates.any?
    
    # Cria os itens do checklist baseado nos templates
    checklist_items = templates.map do |template|
      {
        id: SecureRandom.uuid,
        text: template['text'],
        priority: template['priority'] || 'none',
        required: template['required'] || false,
        completed: false,
        agent_id: Current.user&.id,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    
    self.checklist = checklist_items
  end

  def add_checklist_templates_from_stage(new_stage)
    # Retorna se não há funnel ou nova etapa
    return [] unless funnel.present? && new_stage.present?

    # Busca os templates da nova etapa
    stage_data = funnel.stages&.dig(new_stage)
    return [] unless stage_data.present?

    templates = stage_data['checklist_templates']
    return [] unless templates.present? && templates.is_a?(Array) && templates.any?

    # Inicializa checklist se não existir
    current_checklist = checklist.is_a?(Array) ? checklist : []

    # Cria novos itens do checklist baseado nos templates
    new_checklist_items = templates.map do |template|
      {
        id: SecureRandom.uuid,
        text: template['text'],
        priority: template['priority'] || 'none',
        required: template['required'] || false,
        completed: false,
        agent_id: Current.user&.id,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    # Adiciona os novos itens ao checklist existente
    self.checklist = current_checklist + new_checklist_items

    # Retorna os novos itens para registro de atividades
    new_checklist_items
  end

  def handle_checklist_changes
    return unless saved_change_to_checklist?

    old_checklist = checklist_before_last_save || []
    new_checklist = checklist || []

    # Verificar itens marcados/desmarcados
    old_checklist.each do |old_item|
      new_item = new_checklist.find { |item| item['id'] == old_item['id'] }
      next unless new_item

      if old_item['completed'] != new_item['completed']
        handle_checklist_item_toggled(new_item['text'], new_item['completed'])
      end
    end
  end

  def handle_custom_attributes_changes
    return unless item_details_changed?

    old_details = item_details_before_last_save || {}
    new_details = item_details || {}

    old_custom_attrs = old_details['custom_attributes'] || {}
    new_custom_attrs = new_details['custom_attributes'] || {}

    # Verificar mudanças em atributos customizados
    (old_custom_attrs.keys | new_custom_attrs.keys).each do |key|
      old_value = old_custom_attrs[key]
      new_value = new_custom_attrs[key]

      if old_value != new_value
        handle_custom_attribute_changed(key, old_value, new_value)
      end
    end
  end
end
