class Api::V1::Accounts::KanbanItemsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_item, except: [:index, :create, :reorder, :debug, :reports, :search, :filter, :export, :import, :import_preview]
  before_action :check_stacklab_license, except: [:debug, :export, :import, :import_preview]

  def export
    authorize KanbanItem

    funnel_id = params[:funnel_id]
    
    unless funnel_id.present?
      render json: { error: 'funnel_id is required' }, status: :bad_request
      return
    end

    # Build base query
    items = Current.account.kanban_items
                    .for_funnel(funnel_id)
                    .includes(:funnel, conversation: :contact)

    # Filtrar por prioridades
    if params[:priorities].present? && params[:priorities].is_a?(Array)
      items = items.where("item_details->>'priority' IN (?)", params[:priorities])
    end

    # Filtrar por valor mínimo
    if params[:value_min].present?
      items = items.where("(item_details->>'value')::float >= ?", params[:value_min].to_f)
    end

    # Filtrar por valor máximo
    if params[:value_max].present?
      items = items.where("(item_details->>'value')::float <= ?", params[:value_max].to_f)
    end

    # Filtrar por agente
    if params[:agent_id].present?
      agent_id_int = params[:agent_id].to_i
      items = items.where("EXISTS (
        SELECT 1 FROM jsonb_array_elements(assigned_agents) AS agent 
        WHERE (agent->>'id')::integer = ?
      )", agent_id_int)
    end

    # Filtrar por período (created_at)
    if params[:date_start].present? && params[:date_end].present?
      date_start = Date.parse(params[:date_start]).beginning_of_day
      date_end = Date.parse(params[:date_end]).end_of_day
      items = items.where(created_at: date_start..date_end)
    elsif params[:date_start].present?
      date_start = Date.parse(params[:date_start]).beginning_of_day
      items = items.where("created_at >= ?", date_start)
    elsif params[:date_end].present?
      date_end = Date.parse(params[:date_end]).end_of_day
      items = items.where("created_at <= ?", date_end)
    end

    # Filtrar por período de agendamento (scheduled_at ou deadline_at)
    if params[:scheduled_date_start].present? && params[:scheduled_date_end].present?
      date_start = Date.parse(params[:scheduled_date_start]).beginning_of_day
      date_end = Date.parse(params[:scheduled_date_end]).end_of_day
      items = items.where(
        "(item_details->>'scheduled_at')::date BETWEEN ? AND ? OR (item_details->>'deadline_at')::date BETWEEN ? AND ?",
        date_start.to_date, date_end.to_date, date_start.to_date, date_end.to_date
      )
    elsif params[:scheduled_date_start].present?
      date_start = Date.parse(params[:scheduled_date_start]).beginning_of_day
      items = items.where(
        "(item_details->>'scheduled_at')::date >= ? OR (item_details->>'deadline_at')::date >= ?",
        date_start.to_date, date_start.to_date
      )
    elsif params[:scheduled_date_end].present?
      date_end = Date.parse(params[:scheduled_date_end]).end_of_day
      items = items.where(
        "(item_details->>'scheduled_at')::date <= ? OR (item_details->>'deadline_at')::date <= ?",
        date_end.to_date, date_end.to_date
      )
    end

    # Aplicar ordenação final
    items = items.order(created_at: :desc)

    csv_data = CSV.generate(headers: true) do |csv|
      csv << [
        'ID',
        'Título',
        'Descrição',
        'Status',
        'Prioridade',
        'Valor',
        'Etapa',
        'Funil',
        'Agentes',
        'Cliente',
        'Email',
        'Telefone',
        'Data de Criação',
        'Data de Atualização',
        'Deadline',
        'Conversa ID'
      ]

      items.each do |item|
        details = item.item_details || {}
        agents = item.assigned_agents || []
        agent_names = agents.map { |a| a['name'] }.compact.join('; ')
        contact = item.conversation&.contact

        csv << [
          item.id,
          details['title'],
          details['description'],
          details['status'],
          details['priority'],
          details['value'],
          item.funnel_stage,
          item.funnel&.name,
          agent_names,
          details['customer_name'] || contact&.name,
          details['customer_email'] || contact&.email,
          details['customer_phone'] || contact&.phone_number,
          item.created_at,
          item.updated_at,
          details['deadline_at'],
          item.conversation_display_id
        ]
      end
    end

    send_data csv_data, 
              type: 'text/csv; charset=utf-8',
              disposition: "attachment; filename=kanban_items_#{funnel_id}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv"
  end

  def import_preview
    authorize KanbanItem

    unless params[:file].present?
      render json: { error: 'Arquivo CSV é obrigatório' }, status: :bad_request
      return
    end

    begin
      file = params[:file]
      csv_data = file.read
      
      # Garantir encoding UTF-8
      utf8_data = csv_data.force_encoding('UTF-8')
      clean_data = utf8_data.valid_encoding? ? utf8_data : utf8_data.encode('UTF-16le', invalid: :replace, replace: '').encode('UTF-8')
      
      csv = CSV.parse(clean_data, headers: true)
      
      # Retornar as colunas do CSV e um preview das primeiras linhas
      preview_rows = csv.first(5).map(&:to_h)
      
      render json: {
        columns: csv.headers || [],
        preview_rows: preview_rows,
        total_rows: csv.count
      }
    rescue CSV::MalformedCSVError => e
      render json: { error: "Erro ao processar CSV: #{e.message}" }, status: :unprocessable_entity
    rescue => e
      render json: { error: "Erro ao ler arquivo: #{e.message}" }, status: :internal_server_error
    end
  end

  def import
    authorize KanbanItem

    funnel_id = params[:funnel_id]
    default_stage_id = params[:default_stage_id]
    mappings_param = params[:mappings]
    
    # Parse mappings se vier como JSON string
    mappings = if mappings_param.is_a?(String)
                 JSON.parse(mappings_param) rescue {}
               else
                 mappings_param || {}
               end
    
    file = params[:file]

    unless funnel_id.present?
      render json: { error: 'funnel_id é obrigatório' }, status: :bad_request
      return
    end

    unless file.present?
      render json: { error: 'Arquivo CSV é obrigatório' }, status: :bad_request
      return
    end

    funnel = Current.account.funnels.find_by(id: funnel_id)
    unless funnel
      render json: { error: 'Funil não encontrado' }, status: :not_found
      return
    end

    begin
      csv_data = file.read
      
      # Garantir encoding UTF-8
      utf8_data = csv_data.force_encoding('UTF-8')
      clean_data = utf8_data.valid_encoding? ? utf8_data : utf8_data.encode('UTF-16le', invalid: :replace, replace: '').encode('UTF-8')
      
      csv = CSV.parse(clean_data, headers: true)
      
      created_count = 0
      error_count = 0
      errors = []

      # Obter a maior posição atual para os novos itens
      max_position = Current.account.kanban_items
                               .for_funnel(funnel_id)
                               .maximum(:position) || 0

      csv.each_with_index do |row, index|
        begin
          item_data = build_item_from_csv_row(row, mappings, funnel_id, default_stage_id)
          
          # Validar dados mínimos
          if item_data[:item_details][:title].blank?
            error_count += 1
            errors << { row: index + 2, error: 'Título é obrigatório' }
            next
          end

          # Definir posição sequencial
          max_position += 1
          item_data[:position] = max_position

          # Criar o item
          kanban_item = Current.account.kanban_items.new(item_data)
          
          if kanban_item.save
            webhook_service.notify_item_created(kanban_item)
            created_count += 1
          else
            error_count += 1
            errors << { 
              row: index + 2, 
              error: kanban_item.errors.full_messages.join(', ') 
            }
          end
        rescue => e
          error_count += 1
          errors << { row: index + 2, error: e.message }
        end
      end

      render json: {
        success: true,
        created_count: created_count,
        error_count: error_count,
        total_rows: csv.count,
        errors: errors.first(50) # Limitar a 50 erros para não sobrecarregar a resposta
      }
    rescue CSV::MalformedCSVError => e
      render json: { error: "Erro ao processar CSV: #{e.message}" }, status: :unprocessable_entity
    rescue => e
      render json: { error: "Erro ao importar: #{e.message}" }, status: :internal_server_error
    end
  end

  def reports
    authorize KanbanItem

    permitted_params = index_params
    funnel_id = permitted_params[:funnel_id]
    
    # Timestamps podem vir em segundos ou milissegundos
    from_param = permitted_params[:from].to_i
    to_param = permitted_params[:to].to_i
    
    # Se o timestamp tem mais de 10 dígitos, está em milissegundos
    from = from_param > 9999999999 ? Time.at(from_param / 1000) : Time.at(from_param)
    to = to_param > 9999999999 ? Time.at(to_param / 1000) : Time.at(to_param)
    
    # Se não foram fornecidos, usar padrão
    from = 30.days.ago if from_param.zero?
    to = Time.current if to_param.zero?
    
    agent_ids = permitted_params[:user_ids]

    # Build base query
    items = Current.account.kanban_items
    items = items.where(created_at: from..to)
    
    if funnel_id.present?
      items = items.for_funnel(funnel_id)
      Rails.logger.info "[KanbanReports] Buscando dados do funil específico: #{funnel_id}"
    else
      Rails.logger.info "[KanbanReports] Buscando dados de TODOS OS FUNIS (funnel_id não enviado)"
    end
    
    # Filtro de agentes simplificado
    if agent_ids.present? && agent_ids.is_a?(Array)
      agent_ids_int = agent_ids.map(&:to_i)
      placeholders = agent_ids_int.map { '?' }.join(',')
      items = items.where("EXISTS (
        SELECT 1 FROM jsonb_array_elements(assigned_agents) AS agent 
        WHERE (agent->>'id')::integer IN (#{placeholders})
      )", *agent_ids_int)
    end

    # Debug detalhado
    Rails.logger.info "[KanbanReports] Parâmetros recebidos: funnel_id=#{funnel_id.inspect}, from=#{from}, to=#{to}, agents=#{agent_ids.inspect}"
    Rails.logger.info "[KanbanReports] Total de items encontrados: #{items.count}"

    # Calculate metrics
    metrics = calculate_report_metrics(items, from, to)

    render json: metrics
  end

  def index
    authorize KanbanItem

    # Permitir explicitamente os parâmetros de filtro
    permitted_params = index_params

    # Memoizar parâmetros processados
    @funnel_id ||= permitted_params[:funnel_id]
    @stage_id ||= permitted_params[:stage_id]
    @agent_id ||= permitted_params[:agent_id]
    @page ||= permitted_params[:page].to_i > 0 ? permitted_params[:page].to_i : 1
    @limit ||= 100  # 100 itens por etapa

    # Memoizar queries
    @base_query ||= build_base_query
    @items_query ||= build_items_query

    # Aplicar paginação
    @items ||= fetch_paginated_items

    # Verificar se há mais itens
    @pagination_data ||= build_pagination_data

    # Serialização dos itens paginados com metadados (formato index com counts)
    @kanban_items_data = {
      items: fetch_items_with_cache,
      pagination: @pagination_data
    }

    render json: @kanban_items_data
  end

  def search
    # authorize KanbanItem  # Temporariamente removido para debug

    permitted_params = index_params
    query = permitted_params[:query].to_s.strip
    funnel_id = permitted_params[:funnel_id]

    Rails.logger.info("[KanbanItemsController#search] Query: #{query}, Funnel: #{funnel_id}")

    # Se não há query, retornar vazio
    if query.blank?
      render json: { items: [], total: 0 }
      return
    end

    # Build base query com filtros básicos
    base_query = Current.account.kanban_items

    Rails.logger.info("[KanbanItemsController#search] Total items before filters: #{base_query.count}")

    # Filtrar por agente se usuário não for admin
    # base_query = base_query.assigned_to_agent(Current.user.id) unless Current.account_user.administrator?

    # Filtrar por funil se fornecido
    if funnel_id.present?
      base_query = base_query.where(funnel_id: funnel_id)
      Rails.logger.info("[KanbanItemsController#search] After funnel filter: #{base_query.count}")
    end

    # Aplicar busca por texto
    search_query = base_query.where(
      "item_details->>'title' ILIKE :query OR " +
      "item_details->>'description' ILIKE :query OR " +
      "item_details->>'customer_name' ILIKE :query OR " +
      "item_details->>'customer_email' ILIKE :query",
      query: "%#{query}%"
    )

    Rails.logger.info("[KanbanItemsController#search] After text search: #{search_query.count}")

    # Limitar resultados para performance
    items = search_query.includes(
      :attachments_attachments,
      :funnel,
      conversation: [:contact, :inbox]
    ).order(created_at: :desc).limit(100)

    # Serializar itens
    serialized_items = items.map do |item|
      cache_key = "kanban_item_search:#{item.id}:#{item.updated_at.to_i}"
      Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
        item.as_json(for_index: true)
      end
    end

    Rails.logger.info("[KanbanItemsController#search] Serialized items: #{serialized_items.length}")

    render json: {
      items: serialized_items,
      total: serialized_items.length,
      query: query
    }
  rescue => e
    Rails.logger.error("Error in search: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render json: { error: e.message }, status: :internal_server_error
  end

  def filter
    authorize KanbanItem

    permitted_params = index_params
    funnel_id = permitted_params[:funnel_id]

    Rails.logger.info("[KanbanItemsController#filter] Params: #{permitted_params.inspect}")

    # Build base query
    base_query = Current.account.kanban_items

    # Filtrar por funil se fornecido
    base_query = base_query.where(funnel_id: funnel_id) if funnel_id.present?

    # Filtrar por prioridades
    if permitted_params[:priorities].present? && permitted_params[:priorities].is_a?(Array)
      base_query = base_query.where("item_details->>'priority' IN (?)", permitted_params[:priorities])
    end

    # Filtrar por valor mínimo
    if permitted_params[:value_min].present?
      base_query = base_query.where("(item_details->>'value')::float >= ?", permitted_params[:value_min].to_f)
    end

    # Filtrar por valor máximo
    if permitted_params[:value_max].present?
      base_query = base_query.where("(item_details->>'value')::float <= ?", permitted_params[:value_max].to_f)
    end

    # Filtrar por agente
    if permitted_params[:agent_id].present?
      agent_id_int = permitted_params[:agent_id].to_i
      base_query = base_query.where("EXISTS (
        SELECT 1 FROM jsonb_array_elements(assigned_agents) AS agent 
        WHERE (agent->>'id')::integer = ?
      )", agent_id_int)
    end

    # Filtrar por período (created_at)
    if permitted_params[:date_start].present? && permitted_params[:date_end].present?
      date_start = Date.parse(permitted_params[:date_start]).beginning_of_day
      date_end = Date.parse(permitted_params[:date_end]).end_of_day
      base_query = base_query.where(created_at: date_start..date_end)
    elsif permitted_params[:date_start].present?
      date_start = Date.parse(permitted_params[:date_start]).beginning_of_day
      base_query = base_query.where("created_at >= ?", date_start)
    elsif permitted_params[:date_end].present?
      date_end = Date.parse(permitted_params[:date_end]).end_of_day
      base_query = base_query.where("created_at <= ?", date_end)
    end

    # Filtrar por período de agendamento (scheduled_at ou deadline_at)
    if permitted_params[:scheduled_date_start].present? && permitted_params[:scheduled_date_end].present?
      date_start = Date.parse(permitted_params[:scheduled_date_start]).beginning_of_day
      date_end = Date.parse(permitted_params[:scheduled_date_end]).end_of_day
      base_query = base_query.where(
        "(item_details->>'scheduled_at')::date BETWEEN ? AND ? OR (item_details->>'deadline_at')::date BETWEEN ? AND ?",
        date_start.to_date, date_end.to_date, date_start.to_date, date_end.to_date
      )
    elsif permitted_params[:scheduled_date_start].present?
      date_start = Date.parse(permitted_params[:scheduled_date_start]).beginning_of_day
      base_query = base_query.where(
        "(item_details->>'scheduled_at')::date >= ? OR (item_details->>'deadline_at')::date >= ?",
        date_start.to_date, date_start.to_date
      )
    elsif permitted_params[:scheduled_date_end].present?
      date_end = Date.parse(permitted_params[:scheduled_date_end]).end_of_day
      base_query = base_query.where(
        "(item_details->>'scheduled_at')::date <= ? OR (item_details->>'deadline_at')::date <= ?",
        date_end.to_date, date_end.to_date
      )
    end

    Rails.logger.info("[KanbanItemsController#filter] Total items after filters: #{base_query.count}")

    # Buscar itens com includes
    items = base_query.includes(
      :attachments_attachments,
      :funnel,
      conversation: [:contact, :inbox]
    ).order(created_at: :desc).limit(100)

    # Serializar itens
    serialized_items = items.map do |item|
      cache_key = "kanban_item_filter:#{item.id}:#{item.updated_at.to_i}"
      Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
        item.as_json(for_index: true)
      end
    end

    render json: {
      items: serialized_items,
      total: serialized_items.length,
      filters: permitted_params.except(:funnel_id)
    }
  rescue => e
    Rails.logger.error("Error in filter: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render json: { error: e.message }, status: :internal_server_error
  end

  def show
    # authorize @kanban_item

    cache_key = "kanban_item_show:#{@kanban_item.id}:#{@kanban_item.updated_at.to_i}"

    data = Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      # Para show individual, forçar carregamento completo das notas e offers
      json_data = @kanban_item.as_json(for_show: true)

      # Garantir que as notas, offers e custom_attributes estejam completas
      if json_data['item_details'].present?
        json_data['item_details']['notes'] = @kanban_item.item_details['notes'] || []
        json_data['item_details']['offers'] = @kanban_item.item_details['offers'] || []
        json_data['item_details']['custom_attributes'] = @kanban_item.item_details['custom_attributes'] || {}
      end

      json_data
    end

    render json: data
  end

  def create
    @kanban_item = Current.account.kanban_items.new(kanban_item_params)

    # Se houver um conversation_id nos item_details, define o conversation_display_id
    @kanban_item.conversation_display_id = @kanban_item.item_details['conversation_id'] if @kanban_item.item_details['conversation_id'].present?

    # Processar assigned_agents se for um array de IDs
    process_assigned_agents(@kanban_item)

    authorize @kanban_item

    if @kanban_item.save
      webhook_service.notify_item_created(@kanban_item)
      render json: @kanban_item
    else
      render json: { errors: @kanban_item.errors }, status: :unprocessable_entity
    end
  end

  def update
    authorize @kanban_item

    # Capturar mudanças antes de salvar
    changes = {}
    kanban_item_params.each do |key, value|
      next unless @kanban_item.send(key) != value

      changes[key] = {
        from: @kanban_item.send(key),
        to: value
      }
    end

    # Capturar estado anterior do timer
    old_timer_started_at = @kanban_item.timer_started_at
    old_timer_duration = @kanban_item.timer_duration

    @kanban_item.assign_attributes(kanban_item_params)

    # Processar assigned_agents se for um array de IDs
    process_assigned_agents(@kanban_item)

    if @kanban_item.save
      # Verificar se timer foi iniciado
      if old_timer_started_at.blank? && @kanban_item.timer_started_at.present?
        webhook_service.notify_timer_started(@kanban_item)
      end

      # Verificar se timer foi parado
      if old_timer_started_at.present? && @kanban_item.timer_started_at.blank?
        duration = @kanban_item.timer_duration - (old_timer_duration || 0)
        webhook_service.notify_timer_stopped(@kanban_item, duration)
      end

      webhook_service.notify_item_updated(@kanban_item, changes) if changes.present?
      render json: @kanban_item
    else
      render json: { errors: @kanban_item.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @kanban_item
    item_data = @kanban_item.dup
    @kanban_item.destroy!
    webhook_service.notify_item_deleted(item_data)
    head :ok
  end

  def move_to_stage
    # Verificar se todos os itens obrigatórios do checklist estão completos
    unless @kanban_item.all_required_checklist_items_completed?
      render json: { 
        error: 'Não é possível mover o item. Complete todos os itens obrigatórios do checklist antes de mudar de etapa.' 
      }, status: :unprocessable_entity
      return
    end

    authorize @kanban_item, :move_to_stage?
    from_stage = @kanban_item.funnel_stage
    @kanban_item.funnel_id = params[:funnel_id] if params[:funnel_id].present?
    @kanban_item.move_to_stage(params[:funnel_stage])
    @kanban_item.save! if @kanban_item.changed?

    webhook_service.notify_stage_change(@kanban_item, from_stage, params[:funnel_stage])

    # Retornar o item atualizado
    render json: @kanban_item
  end

  def reorder
    authorize KanbanItem, :reorder?

    # Capturar estado atual antes das mudanças
    current_items = Current.account.kanban_items.where(id: params[:positions].map { |p| p[:id] })
    changes = params[:positions].map do |position|
      current_item = current_items.find { |item| item.id == position[:id].to_i }
      {
        item_id: position[:id],
        old_position: current_item&.position,
        new_position: position[:position],
        old_stage: current_item&.funnel_stage,
        new_stage: position[:funnel_stage]
      }
    end

    # Verificar se algum item está mudando de stage e tem checklist obrigatório pendente
    changes.each do |change|
      if change[:old_stage] != change[:new_stage]
        item = current_items.find { |i| i.id == change[:item_id].to_i }
        unless item.all_required_checklist_items_completed?
          render json: { 
            error: 'Não é possível mover o item. Complete todos os itens obrigatórios do checklist antes de mudar de etapa.',
            item_id: item.id
          }, status: :unprocessable_entity
          return
        end
      end
    end

    ActiveRecord::Base.transaction do
      # Carregar todos os itens uma vez para evitar N+1
      items_to_update = Current.account.kanban_items.where(id: params[:positions].map { |p| p[:id] }).index_by(&:id)

      params[:positions].each do |position|
        item = items_to_update[position[:id]]
        next unless item

        item.update!(
          position: position[:position],
          funnel_stage: position[:funnel_stage]
        )
        # O updated_at é atualizado automaticamente, invalidando o cache
      end
    end

    # Notificar webhook após a reordenação
    updated_items = Current.account.kanban_items.where(id: params[:positions].map { |p| p[:id] })
    webhook_service.notify_item_reordered(updated_items, changes)

    head :ok
  end

  def debug
    authorize KanbanItem
    funnel_id = params[:funnel_id]

    kanban_items = Current.account.kanban_items
                          .for_funnel(funnel_id)
                          .order_by_position

    debug_info = {
      environment: Rails.env,
      ruby_version: RUBY_VERSION,
      rails_version: Rails::VERSION::STRING,
      kanban_items_count: kanban_items.size,
      first_item_sample: kanban_items.first&.as_json,
      has_conversation_data: kanban_items.any? { |item| item.item_details['conversation_id'].present? }
    }

    render json: debug_info
  end

  # Método simples para mover o item
  def move
    # Verificar se está mudando de stage e tem checklist obrigatório pendente
    if params[:funnel_stage] && params[:funnel_stage] != @kanban_item.funnel_stage
      unless @kanban_item.all_required_checklist_items_completed?
        render json: { 
          error: 'Não é possível mover o item. Complete todos os itens obrigatórios do checklist antes de mudar de etapa.' 
        }, status: :unprocessable_entity
        return
      end
    end

    authorize @kanban_item
    old_funnel_id = @kanban_item.funnel_id
    old_stage = @kanban_item.funnel_stage

    @kanban_item.update!(
      funnel_id: params[:funnel_id],
      funnel_stage: params[:funnel_stage]
    )

    render json: @kanban_item
  end

  # Método para criar item na checklist
  def create_checklist_item
    authorize @kanban_item

    # Garantir que checklist seja sempre um Array, mesmo que venha como Hash do index
    checklist = if @kanban_item.checklist.is_a?(Array)
                  @kanban_item.checklist
                elsif @kanban_item.checklist.is_a?(Hash)
                  # Se for um Hash (formato index), converter para Array vazio
                  []
                else
                  []
                end

    checklist_item = {
      id: SecureRandom.uuid,
      text: params[:text],
      completed: false,
      created_at: Time.current,
      position: checklist.size,
      due_date: params[:due_date].present? ? Time.parse(params[:due_date]) : nil,
      priority: params[:priority].presence || 'none',
      agent_id: params[:agent_id]
    }
    checklist << checklist_item
    @kanban_item.checklist = checklist
    @kanban_item.save!

    webhook_service.notify_checklist_item_created(@kanban_item, checklist_item)

    render json: @kanban_item
  end

  # Método para criar nota
  def create_note
    authorize @kanban_item

    # Usar o método seguro do modelo para adicionar notas
    note_data = {
      text: params[:text],
      author: Current.user.name,
      author_id: Current.user.id,
      attachments: params[:attachments] || [],
      linked_item_id: params[:linked_item_id],
      linked_conversation_id: params[:linked_conversation_id],
      linked_contact_id: params[:linked_contact_id]
    }

    @kanban_item.add_note(note_data)
    
    # Buscar a nota criada para enviar no webhook
    notes = @kanban_item.normalized_notes
    created_note = notes.last
    webhook_service.notify_note_created(@kanban_item, created_note) if created_note

    render json: @kanban_item
  end

  # Método para buscar notas do item
  def get_notes
    authorize @kanban_item

    notes = @kanban_item.item_details['notes'] || []

    render json: {
      item_id: @kanban_item.id,
      notes: notes,
      notes_count: notes.length
    }
  end

  # Método para atualizar nota
  def update_note
    authorize @kanban_item

    note_id = params[:note_id]

    # Validar parâmetro
    unless note_id.present?
      render json: { error: 'note_id is required' }, status: :bad_request
      return
    end

    # Buscar a nota
    notes = @kanban_item.normalized_notes
    note = notes.find { |n| n['id'] == note_id }

    unless note
      render json: { error: 'Note not found' }, status: :not_found
      return
    end

    # Atualizar campos permitidos
    update_params = params.permit(:text, :linked_item_id, :linked_conversation_id, :linked_contact_id, attachments: [])
    note_data = {}
    note_data[:text] = update_params[:text] if update_params.key?(:text)
    note_data[:attachments] = update_params[:attachments] if update_params.key?(:attachments)
    note_data[:linked_item_id] = update_params[:linked_item_id] if update_params.key?(:linked_item_id)
    note_data[:linked_conversation_id] = update_params[:linked_conversation_id] if update_params.key?(:linked_conversation_id)
    note_data[:linked_contact_id] = update_params[:linked_contact_id] if update_params.key?(:linked_contact_id)

    @kanban_item.update_note(note_id, note_data)
    
    # Buscar a nota atualizada para enviar no webhook
    notes = @kanban_item.normalized_notes
    updated_note = notes.find { |n| n['id'] == note_id }
    webhook_service.notify_note_updated(@kanban_item, note_id, updated_note) if updated_note

    render json: @kanban_item
  end

  # Método para deletar nota
  def delete_note
    authorize @kanban_item

    note_id = params[:note_id]
    @kanban_item.remove_note(note_id)
    
    webhook_service.notify_note_deleted(@kanban_item, note_id)

    render json: @kanban_item
  end

  # Método para buscar checklist do item
  def get_checklist
    authorize @kanban_item

    checklist = @kanban_item.checklist || []

    render json: {
      item_id: @kanban_item.id,
      checklist: checklist,
      checklist_count: @kanban_item.checklist_count[:total_count]
    }
  end

  # Método para deletar item do checklist
  def delete_checklist_item
    authorize @kanban_item

    checklist_item_id = params[:checklist_item_id]
    @kanban_item.remove_checklist_item(checklist_item_id)
    
    webhook_service.notify_checklist_item_deleted(@kanban_item, checklist_item_id)

    render json: @kanban_item
  end

  # Método para atualizar item do checklist
  def update_checklist_item
    authorize @kanban_item

    checklist_item_id = params[:checklist_item_id]

    # Validar parâmetro
    unless checklist_item_id.present?
      render json: { error: 'checklist_item_id is required' }, status: :bad_request
      return
    end

    # Buscar o item do checklist
    checklist = @kanban_item.checklist || []
    checklist_item = checklist.find { |item| item['id'] == checklist_item_id }

    unless checklist_item
      render json: { error: 'Checklist item not found' }, status: :not_found
      return
    end

    # Atualizar campos permitidos
    update_params = params.permit(:text, :due_date, :priority, :linked_item_id, :linked_conversation_id, :linked_contact_id, :agent_id)
    
    # Atualizar campos do item
    checklist_item['text'] = update_params[:text] if update_params[:text].present?
    checklist_item['due_date'] = update_params[:due_date].present? ? Time.parse(update_params[:due_date]) : nil
    checklist_item['priority'] = update_params[:priority].presence || 'none'
    checklist_item['linked_item_id'] = update_params[:linked_item_id]
    checklist_item['linked_conversation_id'] = update_params[:linked_conversation_id]
    checklist_item['linked_contact_id'] = update_params[:linked_contact_id]
    checklist_item['agent_id'] = update_params[:agent_id]
    checklist_item['updated_at'] = Time.current

    # Salvar as alterações
    @kanban_item.checklist = checklist
    @kanban_item.save!

    webhook_service.notify_checklist_item_updated(@kanban_item, checklist_item_id, checklist_item)

    render json: @kanban_item
  end

  # Método para marcar/desmarcar item do checklist
  def toggle_checklist_item
    authorize @kanban_item

    checklist_item_id = params[:checklist_item_id]

    # Validar parâmetro
    unless checklist_item_id.present?
      render json: { error: 'checklist_item_id is required' }, status: :bad_request
      return
    end

    # Buscar o item do checklist
    checklist = @kanban_item.checklist || []
    checklist_item = checklist.find { |item| item['id'] == checklist_item_id }

    unless checklist_item
      render json: { error: 'Checklist item not found' }, status: :not_found
      return
    end

    # Toggle o status completed
    old_completed = checklist_item['completed']
    checklist_item['completed'] = !checklist_item['completed']
    checklist_item['updated_at'] = Time.current

    # Salvar as alterações
    @kanban_item.checklist = checklist
    @kanban_item.save!

    webhook_service.notify_checklist_item_toggled(@kanban_item, checklist_item_id, checklist_item['completed'])
    
    # Notificar se item obrigatório foi completado
    if checklist_item['required'] && checklist_item['completed'] && !old_completed
      webhook_service.notify_checklist_item_completed(@kanban_item, checklist_item_id)
    end

    render json: @kanban_item
  end


  # Método para atribuir agente (atualizado para múltiplos agentes)
  def assign_agent
    authorize @kanban_item

    agent_id = params[:agent_id]

    unless agent_id.present?
      render json: { error: 'agent_id is required' }, status: :bad_request
      return
    end

    if @kanban_item.agent_assigned?(agent_id)
      render json: { error: 'Agent already assigned to this item' }, status: :unprocessable_entity
    elsif @kanban_item.assign_agent(agent_id, Current.user)
      agent = User.find_by(id: agent_id)
      agent_data = agent ? { id: agent.id, name: agent.name, email: agent.email } : {}
      webhook_service.notify_agent_assigned(@kanban_item, agent_id, agent_data)
      render json: @kanban_item
    else
      render json: { error: 'Failed to assign agent' }, status: :unprocessable_entity
    end
  end

  # Método para remover agente
  def remove_agent
    authorize @kanban_item

    agent_id = params[:agent_id]

    unless agent_id.present?
      render json: { error: 'agent_id is required' }, status: :bad_request
      return
    end

    if @kanban_item.remove_agent(agent_id)
      webhook_service.notify_agent_removed(@kanban_item, agent_id)
      render json: @kanban_item
    else
      render json: { error: 'Failed to remove agent or agent not found' }, status: :unprocessable_entity
    end
  end

  # Método para listar agentes atribuídos
  def assigned_agents
    authorize @kanban_item

    render json: {
      assigned_agents: @kanban_item.assigned_agents_data,
      primary_agent: @kanban_item.primary_agent&.as_json(only: %i[id name email avatar_url availability_status])
    }
  end

  # Método para mudar status
  def change_status
    authorize @kanban_item

    status = params[:status]
    allowed_statuses = %w[won lost open]

    unless allowed_statuses.include?(status)
      render json: { error: "Status must be one of: #{allowed_statuses.join(', ')}" }, status: :unprocessable_entity
      return
    end

    old_status = @kanban_item.item_details['status']
    @kanban_item.item_details['status'] = status
    @kanban_item.save!

    webhook_service.notify_status_changed(@kanban_item, old_status, status) if old_status != status

    render json: @kanban_item
  end

  # Método para atribuir agente a um item específico do checklist
  def assign_agent_to_checklist_item
    authorize @kanban_item

    checklist_item_id = params[:checklist_item_id]
    agent_id = params[:agent_id]

    # Validar parâmetros
    unless checklist_item_id.present? && agent_id.present?
      render json: { error: 'checklist_item_id and agent_id are required' }, status: :bad_request
      return
    end

    # Buscar o item do checklist
    checklist = @kanban_item.checklist || []
    checklist_item = checklist.find { |item| item['id'] == checklist_item_id }

    unless checklist_item
      render json: { error: 'Checklist item not found' }, status: :not_found
      return
    end

    # Atualizar o agente do item
    checklist_item['agent_id'] = agent_id
    checklist_item['updated_at'] = Time.current

    # Salvar as alterações
    @kanban_item.checklist = checklist
    @kanban_item.save!

    webhook_service.notify_checklist_item_agent_assigned(@kanban_item, checklist_item_id, agent_id)

    render json: @kanban_item
  end

  # Método para remover agente de um item específico do checklist
  def remove_agent_from_checklist_item
    authorize @kanban_item

    checklist_item_id = params[:checklist_item_id]

    # Validar parâmetros
    unless checklist_item_id.present?
      render json: { error: 'checklist_item_id is required' }, status: :bad_request
      return
    end

    # Buscar o item do checklist
    checklist = @kanban_item.checklist || []
    checklist_item = checklist.find { |item| item['id'] == checklist_item_id }

    unless checklist_item
      render json: { error: 'Checklist item not found' }, status: :not_found
      return
    end

    # Capturar o agent_id antes de remover para invalidar o cache
    agent_id = checklist_item['agent_id']

    # Remover o agente do item
    checklist_item.delete('agent_id')
    checklist_item['updated_at'] = Time.current

    # Salvar as alterações
    @kanban_item.checklist = checklist
    @kanban_item.save!

    webhook_service.notify_checklist_item_agent_removed(@kanban_item, checklist_item_id, agent_id) if agent_id

    render json: @kanban_item
  end

  # Relatório de tempo total gasto no item
  def time_report
    authorize @kanban_item

    # Calcular tempo total baseado no timer_duration + tempo atual se timer estiver rodando
    total_duration = @kanban_item.timer_duration || 0

    if @kanban_item.timer_started_at.present?
      # Usar stop_timer para calcular a sessão atual sem parar o timer
      current_session = Time.current - @kanban_item.timer_started_at
      total_duration += current_session.to_i
    end

    render json: {
      item_id: @kanban_item.id,
      total_duration_seconds: total_duration,
      total_duration_formatted: format_duration(total_duration),
      timer_started_at: @kanban_item.timer_started_at,
      is_timer_running: @kanban_item.timer_started_at.present?,
      created_at: @kanban_item.created_at
    }
  end

  # Timer detalhado por etapa
  def stage_time_breakdown
    authorize @kanban_item

    # Buscar atividades de mudança de etapa
    activities = @kanban_item.activities || []
    stage_changes = activities.select { |activity| activity['type'] == 'stage_changed' }

    breakdown = {}
    previous_change = nil

    # Adicionar mudança inicial (criação do item)
    if @kanban_item.created_at.present?
      breakdown['initial'] = {
        stage: 'new',
        entered_at: @kanban_item.created_at,
        duration_seconds: 0
      }
      previous_change = @kanban_item.created_at
    end

    # Processar cada mudança de etapa
    stage_changes.each do |change|
      current_stage = change['details']['new_stage']
      entered_at = Time.parse(change['created_at'])

      if previous_change
        duration = (entered_at - previous_change).to_i
        breakdown[change['id'].to_s] = {
          stage: current_stage,
          entered_at: entered_at,
          duration_seconds: duration,
          duration_formatted: format_duration(duration)
        }
      end

      previous_change = entered_at
    end

    # Adicionar tempo na etapa atual
    if previous_change && @kanban_item.stage_entered_at
      current_duration = @kanban_item.time_in_current_stage
      breakdown['current'] = {
        stage: @kanban_item.funnel_stage,
        entered_at: @kanban_item.stage_entered_at,
        duration_seconds: current_duration,
        duration_formatted: format_duration(current_duration)
      }
    end

    render json: {
      item_id: @kanban_item.id,
      stage_breakdown: breakdown,
      total_stages: breakdown.keys.length
    }
  end

  # Duplicar checklist para outro item
  def duplicate_checklist
    authorize @kanban_item

    target_item_id = params[:target_item_id]
    target_item = Current.account.kanban_items.find_by(id: target_item_id)

    unless target_item
      render json: { error: 'Target item not found' }, status: :not_found
      return
    end

    authorize target_item, :update?

    # Duplicar checklist
    source_checklist = @kanban_item.checklist || []
    duplicated_checklist = source_checklist.map do |item|
      item.merge(
        'id' => SecureRandom.uuid,
        'completed' => false,
        'created_at' => Time.current
      )
    end

    # Mesclar com checklist existente do target ou substituir
    if params[:merge] == 'true'
      existing_checklist = target_item.checklist || []
      target_item.checklist = existing_checklist + duplicated_checklist
    else
      target_item.checklist = duplicated_checklist
    end

    if target_item.save
      webhook_service.notify_item_updated(target_item, { checklist: 'duplicated' })
      webhook_service.notify_checklist_duplicated(target_item, @kanban_item.id, duplicated_checklist.length)

      render json: {
        source_item_id: @kanban_item.id,
        target_item_id: target_item.id,
        duplicated_items_count: duplicated_checklist.length,
        total_items_count: target_item.checklist_count[:total_count]
      }
    else
      render json: { errors: target_item.errors }, status: :unprocessable_entity
    end
  end

  # Buscar itens no checklist
  def search_checklist
    authorize @kanban_item

    query = params[:query].to_s.strip.downcase
    checklist = @kanban_item.checklist || []

    if query.blank?
      filtered_checklist = checklist
    else
      filtered_checklist = checklist.select do |item|
        item['text'].to_s.downcase.include?(query)
      end
    end

    render json: {
      item_id: @kanban_item.id,
      query: query,
      total_items: @kanban_item.checklist_count[:total_count],
      filtered_items: filtered_checklist.length,
      attachments_count: @kanban_item.attachments_count[:total_count],
      notes_count: @kanban_item.notes_count[:total_count],
      checklist: filtered_checklist
    }
  end

  # Método para buscar counts de notas, checklist e anexos
  def counts
    authorize @kanban_item

    render json: {
      item_id: @kanban_item.id,
      notes_count: @kanban_item.notes_count[:total_count],
      checklist_count: @kanban_item.checklist_count[:total_count],
      attachments_count: @kanban_item.attachments_count[:total_count]
    }
  end

  # Progresso do checklist por agente
  def checklist_progress_by_agent
    authorize @kanban_item

    checklist = @kanban_item.checklist || []
    assigned_agents = @kanban_item.assigned_agents || []

    # Agrupar itens do checklist por agente
    progress_by_agent = {}

    # Inicializar progresso para todos os agentes atribuídos
    assigned_agents.each do |agent|
      progress_by_agent[agent['id']] = {
        agent_id: agent['id'],
        agent_name: agent['name'],
        total_items: 0,
        completed_items: 0,
        pending_items: 0,
        progress_percentage: 0
      }
    end

    # Adicionar categoria para itens não atribuídos
    progress_by_agent['unassigned'] = {
      agent_id: nil,
      agent_name: 'Não atribuído',
      total_items: 0,
      completed_items: 0,
      pending_items: 0,
      progress_percentage: 0
    }

    # Contabilizar progresso por agente
    checklist.each do |item|
      agent_id = item['agent_id'] || 'unassigned'

      # Inicializar se não existir
      progress_by_agent[agent_id] ||= {
        agent_id: agent_id,
        agent_name: assigned_agents.find { |a| a['id'] == agent_id }&.[]('name') || 'Agente removido',
        total_items: 0,
        completed_items: 0,
        pending_items: 0,
        progress_percentage: 0
      }

      progress_by_agent[agent_id][:total_items] += 1

      if item['completed']
        progress_by_agent[agent_id][:completed_items] += 1
      else
        progress_by_agent[agent_id][:pending_items] += 1
      end
    end

    # Calcular porcentagens
    progress_by_agent.each do |agent_id, progress|
      total = progress[:total_items]
      if total > 0
        progress[:progress_percentage] = ((progress[:completed_items].to_f / total) * 100).round(1)
      end
    end

    # Remover entradas vazias (agentes sem itens)
    progress_by_agent.reject! { |_, progress| progress[:total_items] == 0 }

    render json: {
      item_id: @kanban_item.id,
      checklist_total_items: @kanban_item.checklist_count[:total_count],
      progress_by_agent: progress_by_agent.values,
      summary: {
        total_agents_with_items: progress_by_agent.keys.length,
        completed_items: @kanban_item.checklist_count[:completed_count],
        pending_items: @kanban_item.checklist_count[:total_count] - @kanban_item.checklist_count[:completed_count]
      }
    }
  end

  # AÇÕES EM MASSA

  # Mover múltiplos itens para uma nova etapa
  def bulk_move_items
    item_ids = params[:item_ids]
    new_stage = params[:new_stage]
    funnel_id = params[:funnel_id]

    # Validações
    unless item_ids.present? && item_ids.is_a?(Array)
      render json: { error: 'item_ids array is required' }, status: :bad_request
      return
    end

    unless new_stage.present?
      render json: { error: 'new_stage is required' }, status: :bad_request
      return
    end

    # Buscar itens e verificar autorização
    items = Current.account.kanban_items.where(id: item_ids)

    if items.empty?
      render json: { error: 'No valid items found' }, status: :not_found
      return
    end

    # Verificar autorização para todos os itens
    items.each do |item|
      authorize item, :move_to_stage?
    end

    # Executar movimento em massa
    moved_count = 0
    errors = []

    ActiveRecord::Base.transaction do
      items.each do |item|
        begin
          # Verificar se todos os itens obrigatórios do checklist estão completos
          unless item.all_required_checklist_items_completed?
            errors << { 
              item_id: item.id, 
              error: 'Complete todos os itens obrigatórios do checklist antes de mudar de etapa.' 
            }
            next
          end

          item.funnel_id = funnel_id if funnel_id.present?
          item.move_to_stage(new_stage)
          item.save!
          moved_count += 1

          # Notificar webhook
          webhook_service.notify_stage_change(item, item.funnel_stage_was, new_stage)
        rescue => e
          errors << { item_id: item.id, error: e.message }
        end
      end
    end

    # Notificar webhook de ação em massa
    if moved_count > 0
      moved_items = Current.account.kanban_items.where(id: item_ids).where(funnel_stage: new_stage)
      webhook_service.notify_bulk_moved(moved_items, new_stage)
    end

    render json: {
      success: true,
      moved_count: moved_count,
      total_requested: item_ids.length,
      errors: errors,
      new_stage: new_stage
    }
  end

  # Atribuir agente para múltiplos itens
  def bulk_assign_agent
    item_ids = params[:item_ids]
    agent_id = params[:agent_id]
    mode = params[:mode] || 'replace' # 'replace' ou 'add'

    # Validações
    unless item_ids.present? && item_ids.is_a?(Array)
      render json: { error: 'item_ids array is required' }, status: :bad_request
      return
    end

    unless agent_id.present?
      render json: { error: 'agent_id is required' }, status: :bad_request
      return
    end

    unless ['replace', 'add'].include?(mode)
      render json: { error: 'mode must be "replace" or "add"' }, status: :bad_request
      return
    end

    # Verificar se o agente existe
    agent = User.find_by(id: agent_id)
    unless agent
      render json: { error: 'Agent not found' }, status: :not_found
      return
    end

    # Buscar itens e verificar autorização
    items = Current.account.kanban_items.where(id: item_ids)

    if items.empty?
      render json: { error: 'No valid items found' }, status: :not_found
      return
    end

    # Verificar autorização para todos os itens
    items.each do |item|
      authorize item, :update?
    end

    # Executar atribuição em massa
    assigned_count = 0
    errors = []

    ActiveRecord::Base.transaction do
      items.each do |item|
        begin
          if mode == 'replace'
            # Remover agentes atuais e adicionar novo
            item.assigned_agents = []
            item.assign_agent(agent_id, Current.user)
          else # mode == 'add'
            # Apenas adicionar agente (não substituir existentes)
            item.assign_agent(agent_id, Current.user)
          end
          assigned_count += 1
        rescue => e
          errors << { item_id: item.id, error: e.message }
        end
      end
    end

    # Notificar webhook de ação em massa
    if assigned_count > 0
      assigned_items = Current.account.kanban_items.where(id: item_ids)
      agent_data = { id: agent.id, name: agent.name, email: agent.email }
      webhook_service.notify_bulk_assigned(assigned_items, agent_id, agent_data)
    end

    render json: {
      success: true,
      assigned_count: assigned_count,
      total_requested: item_ids.length,
      errors: errors,
      agent_id: agent_id,
      agent_name: agent.name,
      mode: mode
    }
  end

  # Aplicar prioridade para múltiplos itens
  def bulk_set_priority
    item_ids = params[:item_ids]
    priority = params[:priority]

    # Validações
    unless item_ids.present? && item_ids.is_a?(Array)
      render json: { error: 'item_ids array is required' }, status: :bad_request
      return
    end

    unless priority.present?
      render json: { error: 'priority is required' }, status: :bad_request
      return
    end

    valid_priorities = ['high', 'medium', 'low', 'urgent', 'none']
    unless valid_priorities.include?(priority.downcase)
      render json: { error: "priority must be one of: #{valid_priorities.join(', ')}" }, status: :bad_request
      return
    end

    # Buscar itens e verificar autorização
    items = Current.account.kanban_items.where(id: item_ids)

    if items.empty?
      render json: { error: 'No valid items found' }, status: :not_found
      return
    end

    # Verificar autorização para todos os itens
    items.each do |item|
      authorize item, :update?
    end

    # Executar atualização de prioridade em massa
    updated_count = 0
    errors = []

    ActiveRecord::Base.transaction do
      items.each do |item|
        begin
          item.item_details['priority'] = priority.downcase
          item.save!
          updated_count += 1

          # Notificar webhook
          webhook_service.notify_item_updated(item, { priority: priority })
        rescue => e
          errors << { item_id: item.id, error: e.message }
        end
      end
    end

    # Notificar webhook de ação em massa
    if updated_count > 0
      updated_items = Current.account.kanban_items.where(id: item_ids)
      webhook_service.notify_bulk_priority_changed(updated_items, priority)
    end

    render json: {
      success: true,
      updated_count: updated_count,
      total_requested: item_ids.length,
      errors: errors,
      priority: priority
    }
  end

  private

  def calculate_report_metrics(items, from, to)
    today = Time.current.beginning_of_day
    this_week = 7.days.ago
    this_month = 30.days.ago

    # Initialize metrics structure
    metrics = {
      totalItems: 0,
      itemsByStage: {},
      averageValue: 0,
      totalValue: 0,
      avgTimeInStage: {},
      conversionRates: {},
      stageMetrics: {
        valueByStage: {},
        itemsCreatedToday: 0,
        itemsCreatedThisWeek: 0,
        itemsCreatedThisMonth: 0,
        stageVelocity: {},
        avgTimeToConversion: {},
        stageEfficiency: {},
        itemsWithDeadline: 0,
        itemsWithRescheduling: 0,
        itemsWithOffers: 0,
        avgOffersValue: 0,
        totalOffers: 0,
        offerRanges: { low: 0, medium: 0, high: 0 },
        priorityDistribution: { low: 0, medium: 0, high: 0 },
        channelDistribution: {}
      },
      checklistMetrics: {
        totalTasks: 0,
        completedTasks: 0,
        completionRate: 0,
        itemsWithChecklists: 0,
        averageTasksPerItem: 0
      },
      activityMetrics: {
        totalActivities: 0,
        activitiesByType: {},
        averageActivitiesPerItem: 0,
        itemsWithNotes: 0,
        itemsWithAttachments: 0,
        stageChanges: 0,
        valueChanges: 0,
        agentChanges: 0,
        itemsWithConversations: 0
      },
      contactMetrics: {
        totalContacts: 0,
        contactsWithEmail: 0,
        contactsWithPhone: 0,
        contactsWithBoth: 0
      },
      productivityMetrics: {
        conversionRate: 0,
        averageTicketWon: 0,
        totalValueLost: 0,
        salesCycle: 0,
        checklistMetrics: {
          openItems: 0,
          wonItems: 0,
          lostItems: 0,
          totalItems: 0
        },
        activityMetrics: {
          byType: {
            stage_changed: 0,
            value_changed: 0,
            agent_changed: 0,
            note_added: 0,
            attachment_added: 0,
            checklist_item_added: 0,
            checklist_item_toggled: 0,
            conversation_linked: 0
          },
          total: 0
        },
        offersMetrics: {
          itemsWithOffers: 0,
          averageOfferValue: 0,
          totalOffers: 0,
          percentageWithOffers: 0
        },
        salesPerformance: {
          won: 0,
          wonPercentage: 0,
          lost: 0,
          lostPercentage: 0,
          open: 0,
          openPercentage: 0
        },
        cycleAnalysis: {
          averageCycle: 0,
          bestCycle: nil,
          worstCycle: nil,
          cycleTimes: []
        }
      },
      salesMetrics: {
        totalRevenue: 0,
        averageTicket: 0,
        closedDeals: 0,
        salesByChannel: {},
        funnelEfficiency: {},
        salesByCategory: {},
        salesByRegion: {},
        monthlyGoal: {
          target: 0,
          achieved: 0,
          percentage: 0
        }
      }
    }

    contact_ids = Set.new

    items.each do |item|
      details = item.item_details || {}
      stage = item.funnel_stage || 'unknown'
      value = details['value'].to_f
      
      # Basic metrics
      metrics[:totalItems] += 1

      # Para eficiência do funil, quando filtro "Todos os Funis" está ativo,
      # incluir nome do funil para diferenciar stages com mesmo nome
      stage_key = @funnel_id.present? ? stage : "#{item.funnel.name}: #{stage}"
      metrics[:itemsByStage][stage_key] = (metrics[:itemsByStage][stage_key] || 0) + 1
      metrics[:totalValue] += value
      metrics[:stageMetrics][:valueByStage][stage] = (metrics[:stageMetrics][:valueByStage][stage] || 0) + value

      # Time-based counts
      created_at = item.created_at
      metrics[:stageMetrics][:itemsCreatedToday] += 1 if created_at >= today
      metrics[:stageMetrics][:itemsCreatedThisWeek] += 1 if created_at >= this_week
      metrics[:stageMetrics][:itemsCreatedThisMonth] += 1 if created_at >= this_month

      # Checklist metrics
      checklist = item.checklist || []
      if checklist.any?
        metrics[:checklistMetrics][:itemsWithChecklists] += 1
        metrics[:checklistMetrics][:totalTasks] += checklist.size
        metrics[:checklistMetrics][:completedTasks] += checklist.count { |t| t['completed'] }
      end

      # Activity metrics
      activities = item.activities || []
      if activities.any?
        metrics[:activityMetrics][:totalActivities] += activities.size
        activities.each do |activity|
          type = activity['type']
          metrics[:activityMetrics][:activitiesByType][type] = (metrics[:activityMetrics][:activitiesByType][type] || 0) + 1
          
          case type
          when 'stage_changed'
            metrics[:activityMetrics][:stageChanges] += 1
          when 'value_changed'
            metrics[:activityMetrics][:valueChanges] += 1
          when 'agent_changed'
            metrics[:activityMetrics][:agentChanges] += 1
          when 'note_added'
            metrics[:activityMetrics][:itemsWithNotes] += 1
          when 'attachment_added'
            metrics[:activityMetrics][:itemsWithAttachments] += 1
          end
        end
      end

      # Priority distribution
      priority = details['priority']
      metrics[:stageMetrics][:priorityDistribution][priority.to_sym] += 1 if %w[low medium high].include?(priority)

      # Channel distribution
      channel = details['channel']
      metrics[:stageMetrics][:channelDistribution][channel] = (metrics[:stageMetrics][:channelDistribution][channel] || 0) + 1 if channel.present?

      # Deadline metrics
      metrics[:stageMetrics][:itemsWithDeadline] += 1 if details['deadline_at'].present?
      metrics[:stageMetrics][:itemsWithRescheduling] += 1 if details['rescheduled']

      # Offers metrics
      offers = details['offers'] || []
      if offers.any?
        metrics[:stageMetrics][:itemsWithOffers] += 1
        metrics[:stageMetrics][:totalOffers] += offers.size
        
        offers_total = offers.sum { |o| o['value'].to_f }
        metrics[:stageMetrics][:avgOffersValue] = offers_total / offers.size if offers.any?

        offers.each do |offer|
          offer_value = offer['value'].to_f
          if offer_value <= 1000
            metrics[:stageMetrics][:offerRanges][:low] += 1
          elsif offer_value <= 5000
            metrics[:stageMetrics][:offerRanges][:medium] += 1
          else
            metrics[:stageMetrics][:offerRanges][:high] += 1
          end
        end
      end

      # Conversation metrics
      metrics[:activityMetrics][:itemsWithConversations] += 1 if item.conversation_display_id.present?

      # Contact metrics (simplified)
      if item.conversation_display_id.present?
        contact_ids.add(item.conversation_display_id)
      end
    end

    # Calculate sales metrics
    calculate_sales_metrics(metrics, items)

    # Calculate productivity metrics
    calculate_productivity_metrics(metrics, items)

    # Calculate averages
    metrics[:averageValue] = metrics[:totalItems] > 0 ? metrics[:totalValue] / metrics[:totalItems] : 0
    metrics[:checklistMetrics][:completionRate] = metrics[:checklistMetrics][:totalTasks] > 0 ?
      metrics[:checklistMetrics][:completedTasks].to_f / metrics[:checklistMetrics][:totalTasks] : 0
    metrics[:checklistMetrics][:averageTasksPerItem] = metrics[:totalItems] > 0 ?
      metrics[:checklistMetrics][:totalTasks].to_f / metrics[:totalItems] : 0
    metrics[:activityMetrics][:averageActivitiesPerItem] = metrics[:totalItems] > 0 ?
      metrics[:activityMetrics][:totalActivities].to_f / metrics[:totalItems] : 0
    metrics[:contactMetrics][:totalContacts] = contact_ids.size

    metrics
  end

  def calculate_productivity_metrics(metrics, items)
    # Initialize variables for productivity calculations
    won_items = []
    lost_items = []
    open_items = []
    cycle_times = []
    total_offers_value = 0
    offers_count = 0

    # Process each item to gather productivity data
    items.each do |item|
      details = item.item_details || {}
      status = details['status']
      value = details['value'].to_f

      # Classify items by status
      case status
      when 'won'
        won_items << item
        metrics[:productivityMetrics][:salesPerformance][:won] += 1
      when 'lost'
        lost_items << item
        metrics[:productivityMetrics][:salesPerformance][:lost] += 1
        metrics[:productivityMetrics][:totalValueLost] += value
      else
        open_items << item
        metrics[:productivityMetrics][:salesPerformance][:open] += 1
      end

      # Calculate cycle time for closed items (won or lost)
      if %w[won lost].include?(status) && item.created_at.present?
        # Look for the first 'stage_changed' activity or use time since creation
        activities = item.activities || []
        stage_changes = activities.select { |a| a['type'] == 'stage_changed' }.sort_by { |a| a['created_at'] }

        if stage_changes.any?
          # Time from creation to first stage change
          first_stage_change = Time.parse(stage_changes.first['created_at']) rescue item.created_at
          cycle_days = ((first_stage_change - item.created_at) / 1.day).round
        else
          # Fallback: time since creation
          cycle_days = ((Time.current - item.created_at) / 1.day).round
        end

        cycle_times << cycle_days if cycle_days > 0
      end

      # Process checklist items by status
      checklist = item.checklist || []
      if checklist.any?
        case status
        when 'won'
          metrics[:productivityMetrics][:checklistMetrics][:wonItems] += 1
        when 'lost'
          metrics[:productivityMetrics][:checklistMetrics][:lostItems] += 1
        else
          metrics[:productivityMetrics][:checklistMetrics][:openItems] += 1
        end
        metrics[:productivityMetrics][:checklistMetrics][:totalItems] += 1
      end

      # Process activities by type for productivity metrics
      activities = item.activities || []
      activities.each do |activity|
        activity_type = activity['type']
        case activity_type
        when 'stage_changed'
          metrics[:productivityMetrics][:activityMetrics][:byType][:stage_changed] += 1
        when 'value_changed'
          metrics[:productivityMetrics][:activityMetrics][:byType][:value_changed] += 1
        when 'agent_changed'
          metrics[:productivityMetrics][:activityMetrics][:byType][:agent_changed] += 1
        when 'note_added'
          metrics[:productivityMetrics][:activityMetrics][:byType][:note_added] += 1
        when 'attachment_added'
          metrics[:productivityMetrics][:activityMetrics][:byType][:attachment_added] += 1
        when 'checklist_item_added'
          metrics[:productivityMetrics][:activityMetrics][:byType][:checklist_item_added] += 1
        when 'checklist_item_toggled'
          metrics[:productivityMetrics][:activityMetrics][:byType][:checklist_item_toggled] += 1
        when 'conversation_linked'
          metrics[:productivityMetrics][:activityMetrics][:byType][:conversation_linked] += 1
        end
        metrics[:productivityMetrics][:activityMetrics][:total] += 1
      end

      # Process offers
      offers = details['offers'] || []
      if offers.any?
        metrics[:productivityMetrics][:offersMetrics][:itemsWithOffers] += 1
        metrics[:productivityMetrics][:offersMetrics][:totalOffers] += offers.size

        offers.each do |offer|
          offer_value = offer['value'].to_f
          total_offers_value += offer_value
          offers_count += 1
        end
      end
    end

    # Calculate final productivity metrics
    total_closed = won_items.size + lost_items.size
    total_items = items.size

    # Conversion rate
    metrics[:productivityMetrics][:conversionRate] = total_closed > 0 ? won_items.size.to_f / total_closed : 0

    # Average ticket won
    metrics[:productivityMetrics][:averageTicketWon] = won_items.any? ?
      won_items.sum { |item| item.item_details['value'].to_f } / won_items.size : 0

    # Sales cycle (average in days)
    metrics[:productivityMetrics][:salesCycle] = cycle_times.any? ? cycle_times.sum / cycle_times.size : 0

    # Sales performance percentages
    if total_items > 0
      metrics[:productivityMetrics][:salesPerformance][:wonPercentage] = (won_items.size.to_f / total_items * 100).round(1)
      metrics[:productivityMetrics][:salesPerformance][:lostPercentage] = (lost_items.size.to_f / total_items * 100).round(1)
      metrics[:productivityMetrics][:salesPerformance][:openPercentage] = (open_items.size.to_f / total_items * 100).round(1)
    end

    # Cycle analysis
    if cycle_times.any?
      metrics[:productivityMetrics][:cycleAnalysis][:averageCycle] = cycle_times.sum / cycle_times.size
      metrics[:productivityMetrics][:cycleAnalysis][:bestCycle] = cycle_times.min
      metrics[:productivityMetrics][:cycleAnalysis][:worstCycle] = cycle_times.max
      metrics[:productivityMetrics][:cycleAnalysis][:cycleTimes] = cycle_times
    end

    # Offers metrics
    if offers_count > 0
      metrics[:productivityMetrics][:offersMetrics][:averageOfferValue] = total_offers_value / offers_count
    end

    if total_items > 0
      metrics[:productivityMetrics][:offersMetrics][:percentageWithOffers] = (metrics[:productivityMetrics][:offersMetrics][:itemsWithOffers].to_f / total_items * 100).round(1)
    end
  end

  def calculate_sales_metrics(metrics, items)
    # Initialize sales variables
    won_items = []
    sales_by_channel = {}
    sales_by_category = {}
    sales_by_region = {}

    # Process each item for sales metrics
    items.each do |item|
      details = item.item_details || {}
      status = details['status']
      value = details['value'].to_f
      channel = details['channel']
      category = details['category'] || details['service_type']
      region = details['region'] || details['location']

      # Only count won deals for sales metrics
      if status == 'won' && value > 0
        won_items << item

        # Sales by channel
        if channel.present?
          sales_by_channel[channel] ||= { count: 0, value: 0 }
          sales_by_channel[channel][:count] += 1
          sales_by_channel[channel][:value] += value
        end

        # Sales by category
        if category.present?
          sales_by_category[category] ||= { count: 0, value: 0 }
          sales_by_category[category][:count] += 1
          sales_by_category[category][:value] += value
        end

        # Sales by region
        if region.present?
          sales_by_region[region] ||= { count: 0, value: 0 }
          sales_by_region[region][:count] += 1
          sales_by_region[region][:value] += value
        end
      end
    end

    # Calculate final sales metrics
    total_revenue = won_items.sum { |item| item.item_details['value'].to_f }
    closed_deals = won_items.size
    average_ticket = closed_deals > 0 ? total_revenue / closed_deals : 0

    # Funnel efficiency (conversion rates by stage)
    total_items = items.size
    funnel_efficiency = {}
    previous_count = total_items

    # Assuming stages are in order, calculate conversion rates
    metrics[:itemsByStage].each do |stage, count|
      if previous_count > 0
        funnel_efficiency[stage] = {
          count: count,
          conversion_rate: (count.to_f / previous_count * 100).round(1)
        }
      else
        funnel_efficiency[stage] = {
          count: count,
          conversion_rate: 0
        }
      end
      previous_count = count
    end

    # Monthly goal (simplified - you might want to make this configurable)
    # For now, using a fixed target or calculating based on historical data
    current_month_start = Time.current.beginning_of_month
    current_month_end = Time.current.end_of_month
    current_month_won_items = won_items.select do |item|
      created_at = item.created_at
      created_at >= current_month_start && created_at <= current_month_end
    end
    current_month_revenue = current_month_won_items.sum { |item| item.item_details['value'].to_f }

    # Calculate target based on average monthly revenue from last 3 months
    # For simplicity, using a fixed target - you can make this configurable
    monthly_target = 120000 # R$ 120.000 as monthly target

    # Update sales metrics
    metrics[:salesMetrics][:totalRevenue] = total_revenue
    metrics[:salesMetrics][:averageTicket] = average_ticket
    metrics[:salesMetrics][:closedDeals] = closed_deals
    metrics[:salesMetrics][:salesByChannel] = sales_by_channel
    metrics[:salesMetrics][:funnelEfficiency] = funnel_efficiency
    metrics[:salesMetrics][:salesByCategory] = sales_by_category
    metrics[:salesMetrics][:salesByRegion] = sales_by_region
    metrics[:salesMetrics][:monthlyGoal][:target] = monthly_target
    metrics[:salesMetrics][:monthlyGoal][:achieved] = current_month_revenue
    metrics[:salesMetrics][:monthlyGoal][:percentage] = monthly_target > 0 ?
      (current_month_revenue / monthly_target * 100).round(1) : 0
  end

  def fetch_items_with_cache
    @items.map do |item|
      cache_key = "kanban_item_index:#{item.id}:#{item.updated_at.to_i}"

      Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
        # Para index, ainda usar versão otimizada, mas forçar notas completas
        json_data = item.as_json(for_index: true)

        # Garantir que as notas, offers, custom_attributes e checklist estejam completas igual no show
        if json_data['item_details'].present?
          json_data['item_details']['notes'] = item.item_details['notes'] || []
          json_data['item_details']['offers'] = item.item_details['offers'] || []
          json_data['item_details']['custom_attributes'] = item.item_details['custom_attributes'] || {}
        end
        json_data['checklist'] = item.checklist || []

        json_data
      end
    end
  end

  def format_duration(seconds)
    return '0s' unless seconds.present? && seconds > 0

    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    secs = seconds % 60

    parts = []
    parts << "#{hours}h" if hours > 0
    parts << "#{minutes}m" if minutes > 0
    parts << "#{secs}s" if secs > 0 || parts.empty?

    parts.join(' ')
  end

  def webhook_service
    @webhook_service ||= KanbanWebhookService.new(Current.account)
  end

  def process_assigned_agents(kanban_item)
    return unless kanban_item.assigned_agents.present?
    return unless kanban_item.assigned_agents.is_a?(Array)

    # Se assigned_agents for um array de IDs, converter para objetos completos
    return unless kanban_item.assigned_agents.first.is_a?(Integer) || kanban_item.assigned_agents.first.is_a?(String)

    agent_ids = kanban_item.assigned_agent_ids
    # Usar index_by para evitar N+1 se houver muitos agents
    agents = Current.account.users.where(id: agent_ids).index_by(&:id)

    processed_agents = agent_ids.map do |agent_id|
      agent = agents[agent_id]
      next unless agent

      {
        id: agent.id,
        name: agent.name,
        email: agent.email,
        avatar_url: agent.avatar_url,
        assigned_at: Time.current,
        assigned_by: Current.user&.id
      }
    end.compact

    kanban_item.assigned_agents = processed_agents
  end

  def fetch_kanban_item
    @kanban_item = Current.account.kanban_items.find(params[:id])
  end

  def build_base_query
    query = Current.account.kanban_items

    # Filtrar por agente se usuário não for admin
    query = query.assigned_to_agent(Current.user.id) unless Current.account_user.administrator?

    query = query.for_funnel(@funnel_id) if @funnel_id.present?
    query = query.in_stage(@stage_id) if @stage_id.present?
    query = query.assigned_to_agent(@agent_id) if @agent_id.present?
    query
  end

  def build_items_query
    @base_query.includes(
      :attachments_attachments,
      :funnel,
      conversation: [:contact, :inbox]
    ).order(created_at: :desc)
  end

  def fetch_paginated_items
    offset = (@page - 1) * @limit
    
    # Se estamos filtrando por stage, precisamos usar uma numeração sequencial
    # ao invés da position global
    if @stage_id.present?
      # Buscar todos os IDs dos itens filtrados ordenados por data de criação
      all_filtered_ids = @base_query.order(created_at: :desc).pluck(:id)
      
      # Pegar apenas os IDs da página atual
      paginated_ids = all_filtered_ids[offset, @limit] || []
      
      # Buscar os itens completos mantendo a ordem
      items = @items_query.where(id: paginated_ids).index_by(&:id)
      paginated_ids.map { |id| items[id] }.compact
    else
      @items_query.limit(@limit).offset(offset).to_a
    end
  end

  def build_pagination_data
    total_count = @base_query.count
    offset = (@page - 1) * @limit
    has_more = (offset + @items.length) < total_count

    {
      current_page: @page,
      total_count: total_count,
      has_more: has_more,
      items_per_page: @limit
    }
  end

  def check_stacklab_license
    # Verifica se o token é válido (mesmo que não seja plano PRO)
    if ChatwootApp.stacklab.token_valid?
      # Se o token é válido mas não é plano PRO, retorna erro específico
      unless ChatwootApp.stacklab?
        render json: {
          error: 'Plano StackLab insuficiente',
          code: 'STACKLAB_PLAN_INSUFFICIENT',
          message: "Esta funcionalidade requer um plano PRO. Plano atual: #{ChatwootApp.stacklab.plan}. #{ChatwootApp.stacklab.message}"
        }, status: :forbidden
        return
      end
      return # Token válido e plano PRO
    end

    # Token inválido ou não configurado
    render json: {
      error: 'Token StackLab não encontrado',
      code: 'STACKLAB_TOKEN_NOT_FOUND',
      message: 'Esta funcionalidade requer uma licença StackLab válida'
    }, status: :not_found
  end

  def index_params
    params.permit(
      :funnel_id,
      :stage_id,
      :agent_id,
      :page,
      :from,
      :to,
      :inbox_id,
      :query,
      :value_min,
      :value_max,
      :date_start,
      :date_end,
      :scheduled_date_start,
      :scheduled_date_end,
      user_ids: [],
      priorities: []
    )
  end

  def kanban_item_params
    params.require(:kanban_item).permit(
      :funnel_id,
      :funnel_stage,
      :position,
      :conversation_display_id,
      :timer_started_at,
      :timer_duration,
      :checklist,
      { checklist: [
        :id, :text, :completed, :created_at, :updated_at, :agent_id, :position, :due_date, :priority
      ] },
      { activities: [
        :id, :type,
        { user: [:id, :name, :avatar_url] },
        { details: [
          { user: [:id, :name, :avatar_url] },
          :new_stage, :old_stage
        ] },
        :created_at
      ] },
      assigned_agents: [],
      custom_attributes: {},
      item_details: [
        :title,
        :description,
        :status,
        :reason,
        :priority,
        :value,
        :currency,
        { currency: [:symbol, :code, :locale] },
        { custom_attributes: [:name, :type, :value, value: []] },
        { offers: [
          :value,
          { currency: [:symbol, :code, :locale] },
          :description
        ] },
        { closed_offer: [
          :value,
          { currency: [:symbol, :code, :locale] },
          :description
        ] },
        :deadline_at,
        :scheduling_type,
        :scheduled_at,
        :conversation_id,
        { automations: [
          :id, :enabled, :trigger_type, :trigger_value, :action,
          { action_config: {} }
        ] },
        { notes: [
          :id, :text, :created_at,
          { attachments: [
            :id, :url, :filename, :byte_size, :content_type, :created_at
          ] },
          :linked_item_id, :linked_conversation_id, :linked_contact_id, :author, :author_id, :author_avatar
        ] }
      ]
    )
  end

  def build_item_from_csv_row(row, mappings, funnel_id, default_stage_id = nil)
    item_details = {}
    assigned_agents = []
    funnel_stage = nil
    conversation_display_id = nil

    # Mapear campos do CSV para o formato do KanbanItem
    mappings.each do |csv_column, field_path|
      next if csv_column.blank? || field_path.blank?

      value = row[csv_column]&.strip
      next if value.blank?

      case field_path
      when 'item_details.title'
        item_details[:title] = value
      when 'item_details.description'
        item_details[:description] = value
      when 'item_details.status'
        item_details[:status] = value.downcase
      when 'item_details.priority'
        item_details[:priority] = value.downcase
      when 'item_details.value'
        item_details[:value] = value.to_f
      when 'item_details.customer_name'
        item_details[:customer_name] = value
      when 'item_details.customer_email'
        item_details[:customer_email] = value
      when 'item_details.customer_phone'
        item_details[:customer_phone] = value
      when 'item_details.deadline_at'
        begin
          item_details[:deadline_at] = Time.parse(value).iso8601
        rescue
          # Se não conseguir parsear, mantém o valor original
          item_details[:deadline_at] = value
        end
      when 'funnel_stage'
        funnel_stage = value
      when 'assigned_agents'
        # Separar múltiplos agentes por ponto e vírgula ou vírgula
        agent_names = value.split(/[;,]/).map(&:strip)
        agent_names.each do |agent_name|
          # Buscar agente por nome ou email
          agent = Current.account.users.find_by('name ILIKE ? OR email ILIKE ?', agent_name, agent_name)
          if agent
            assigned_agents << agent.id
          end
        end
      when 'conversation_display_id'
        conversation_display_id = value.to_i if value.present?
      end
    end

    # Validar que tem pelo menos título e etapa
    if funnel_stage.blank?
      # Usar etapa padrão se fornecida
      if default_stage_id.present?
        funnel_stage = default_stage_id
      else
        # Tentar usar a primeira etapa do funil se não mapeada
        funnel = Current.account.funnels.find_by(id: funnel_id)
        if funnel&.stages&.any?
          funnel_stage = funnel.stages.keys.first
        else
          funnel_stage = 'new'
        end
      end
    end

    # Construir estrutura do item
    item_data = {
      account_id: Current.account.id,
      funnel_id: funnel_id,
      funnel_stage: funnel_stage,
      item_details: item_details,
      conversation_display_id: conversation_display_id
    }

    # Processar assigned_agents se houver
    if assigned_agents.any?
      item_data[:assigned_agents] = assigned_agents.map do |agent_id|
        agent = Current.account.users.find_by(id: agent_id)
        next unless agent

        {
          id: agent.id,
          name: agent.name,
          email: agent.email,
          avatar_url: agent.avatar_url,
          assigned_at: Time.current,
          assigned_by: Current.user&.id
        }
      end.compact
    end

    item_data
  end
end
