class Api::V1::Accounts::FunnelsController < Api::V1::Accounts::BaseController
  before_action :fetch_funnel, except: [:index, :create]
  before_action :check_funnel_limit, only: [:create]
  before_action :check_stacklab_license

  def index
    @funnels = Rails.cache.fetch("funnels_index_#{Current.account.id}", expires_in: 5.minutes) do
      Current.account.funnels.ordered_by_name.to_a
    end
    render json: @funnels
  end

  def show
    @funnel_data = Rails.cache.fetch([@funnel.id, @funnel.updated_at.to_i]) do
      @funnel.as_json
    end
    render json: @funnel_data
  end

  def create
    @funnel = Current.account.funnels.new(funnel_params)

    if @funnel.stages.present?
      # Busca todos os IDs de etapas existentes em todos os funis
      existing_stage_ids = Current.account.funnels.pluck(:stages).compact.flat_map do |stages|
        stages.values.map { |stage| stage['id'] }
      end

      # Ajusta os IDs das etapas e seus templates
      @funnel.stages = @funnel.stages.transform_values do |stage|
        if existing_stage_ids.include?(stage['id'])
          new_id = "#{stage['id']}_#{Time.now.to_i}"
          stage.merge('id' => new_id)
        else
          stage
        end
      end
    end

    if @funnel.save
      Rails.cache.delete("funnels_index_#{Current.account.id}")
      render json: @funnel
    else
      render json: { errors: @funnel.errors }, status: :unprocessable_entity
    end
  end

  def update
    if @funnel.update(funnel_params)
      Rails.cache.delete("funnels_index_#{Current.account.id}")
      Rails.cache.delete([@funnel.id, @funnel.updated_at.to_i])
      render json: @funnel
    else
      render json: { errors: @funnel.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    # Força a exclusão dos itens associados antes de deletar o funil
    @funnel.kanban_items.delete_all
    @funnel.destroy!
    Rails.cache.delete("funnels_index_#{Current.account.id}")
    head :ok
  end

  def stage_stats
    # Memoização dos estágios inicializados
    @stages ||= @funnel.stages.keys.each_with_object({}) do |stage, hash|
      hash[stage.to_sym] = {
        name: @funnel.stages[stage]['name'],
        color: @funnel.stages[stage]['color'],
        description: @funnel.stages[stage]['description'],
        count: 0,
        total_value: 0.0
      }
    end

    # Memoização dos itens filtrados
    @items ||= begin
      items = KanbanItem.where(account_id: current_account.id, funnel_id: @funnel.id)
      items = items.assigned_to_agent(current_user.id) unless current_user.administrator?
      
      # Aplicar filtros de prioridade
      if params[:priorities].present?
        priorities = params[:priorities].is_a?(Array) ? params[:priorities] : [params[:priorities]]
        items = items.where("item_details->>'priority' IN (?)", priorities)
      end
      
      # Aplicar filtro de agente
      if params[:agent_id].present?
        agent_id = params[:agent_id].to_s
        if agent_id == '-1'
          items = items.where("assigned_agents = '[]' OR assigned_agents IS NULL")
        else
          items = items.where("assigned_agents @> ?", [{ id: agent_id.to_i }].to_json)
        end
      end
      
      # Aplicar filtro de valor
      if params[:value_min].present?
        items = items.where("COALESCE((item_details->>'value')::float, 0) >= ?", params[:value_min].to_f)
      end
      if params[:value_max].present?
        items = items.where("COALESCE((item_details->>'value')::float, 0) <= ?", params[:value_max].to_f)
      end
      
      # Aplicar filtro de data
      if params[:date_start].present?
        items = items.where("created_at >= ?", params[:date_start])
      end
      if params[:date_end].present?
        items = items.where("created_at <= ?", params[:date_end])
      end
      
      # Aplicar filtro de status
      show_won = params[:show_won].to_s != 'false'
      show_lost = params[:show_lost].to_s != 'false'
      
      unless show_won && show_lost
        if !show_won && !show_lost
          # Mostrar apenas itens que não são "won" nem "lost" (em andamento)
          items = items.where("(item_details->>'status' IS NULL OR item_details->>'status' = '' OR item_details->>'status' NOT IN ('won', 'lost'))")
        elsif show_won && !show_lost
          items = items.where("item_details->>'status' = 'won' OR item_details->>'status' IS NULL OR item_details->>'status' = ''")
        elsif !show_won && show_lost
          items = items.where("item_details->>'status' = 'lost'")
        end
      end
      
      items
    end

    # Memoização dos dados agrupados
    @grouped ||= @items.group(:funnel_stage)
                       .pluck(
                         :funnel_stage,
                         Arel.sql('COUNT(*)'),
                         Arel.sql("COALESCE(SUM((item_details->>'value')::float),0)")
                       )

    # Preenche os dados no hash stages
    @grouped.each do |stage, count, total_value|
      @stages[stage.to_sym][:count] = count if @stages.key?(stage.to_sym)
      @stages[stage.to_sym][:total_value] = total_value.to_f if @stages.key?(stage.to_sym)
    end

    @stage_stats = {
      stages: @stages,
      total_items: @items.count
    }
    render json: @stage_stats
  end

  private

  def fetch_funnel
    @funnel = Current.account.funnels.find(params[:id])
  end

  def funnel_params
    params.require(:funnel).permit(
      :name,
      :description,
      :active,
      stages: {},
      settings: {},
      global_custom_attributes: [:name, :type, :is_list, list_values: []]
    )
  end

  def check_funnel_limit
    # Usa ChatwootApp.stacklab ao invés de ENV
    return if ChatwootApp.stacklab?

    return unless Current.account.funnels.count >= 2

    render json: {
      error: 'Limite de funis atingido. Atualize para a versão PRO para criar mais funis.',
      code: 'FUNNEL_LIMIT_REACHED'
    }, status: :forbidden
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
end
