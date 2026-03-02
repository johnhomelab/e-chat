# loading installation configs
GlobalConfig.clear_cache
ConfigLoader.new.process

## Seeds productions
if Rails.env.production?
  # Setup Onboarding flow
  Redis::Alfred.set(Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING, true)
end

## Seeds for Local Development
unless Rails.env.production?

  # Enables creating additional accounts from dashboard
  installation_config = InstallationConfig.find_by(name: 'CREATE_NEW_ACCOUNT_FROM_DASHBOARD')
  installation_config.value = true
  installation_config.save!
  GlobalConfig.clear_cache

  account = Account.create!(
    name: 'Acme Inc'
  )

  secondary_account = Account.create!(
    name: 'Acme Org'
  )

  user = User.new(name: 'John', email: 'john@acme.inc', password: 'Password1!', type: 'SuperAdmin')
  user.skip_confirmation!
  user.save!

  AccountUser.create!(
    account_id: account.id,
    user_id: user.id,
    role: :administrator
  )

  AccountUser.create!(
    account_id: secondary_account.id,
    user_id: user.id,
    role: :administrator
  )

  web_widget = Channel::WebWidget.create!(account: account, website_url: 'https://acme.inc')

  inbox = Inbox.create!(channel: web_widget, account: account, name: 'Acme Support')
  InboxMember.create!(user: user, inbox: inbox)

  contact_inbox = ContactInboxWithContactBuilder.new(
    source_id: user.id,
    inbox: inbox,
    hmac_verified: true,
    contact_attributes: { name: 'jane', email: 'jane@example.com', phone_number: '+2320000' }
  ).perform

  conversation = Conversation.create!(
    account: account,
    inbox: inbox,
    status: :open,
    assignee: user,
    contact: contact_inbox.contact,
    contact_inbox: contact_inbox,
    additional_attributes: {}
  )

  # sample email collect
  Seeders::MessageSeeder.create_sample_email_collect_message conversation

  Message.create!(content: 'Hello', account: account, inbox: inbox, conversation: conversation, sender: contact_inbox.contact,
                  message_type: :incoming)

  # sample location message
  #
  location_message = Message.new(content: 'location', account: account, inbox: inbox, sender: contact_inbox.contact, conversation: conversation,
                                 message_type: :incoming)
  location_message.attachments.new(
    account_id: account.id,
    file_type: 'location',
    coordinates_lat: 37.7893768,
    coordinates_long: -122.3895553,
    fallback_title: 'Bay Bridge, San Francisco, CA, USA'
  )
  location_message.save!

  # sample card
  Seeders::MessageSeeder.create_sample_cards_message conversation
  # input select
  Seeders::MessageSeeder.create_sample_input_select_message conversation
  # form
  Seeders::MessageSeeder.create_sample_form_message conversation
  # articles
  Seeders::MessageSeeder.create_sample_articles_message conversation
  # csat
  Seeders::MessageSeeder.create_sample_csat_collect_message conversation

  CannedResponse.create!(account: account, short_code: 'start', content: 'Hello welcome to chatwoot.')

  # Criando um funil de vendas padrão
  sales_funnel = Funnel.create!(
    account_id: account.id,
    name: 'Funil de Vendas',
    description: 'Funil padrão para gestão de vendas',
    active: true,
    stages: {
      'lead' => {
        name: 'Lead',
        description: 'Potenciais clientes',
        color: '#FF6B6B',
        position: 1
      },
      'contact' => {
        name: 'Contato Realizado',
        description: 'Primeiro contato estabelecido',
        color: '#4ECDC4',
        position: 2
      },
      'proposal' => {
        name: 'Proposta Enviada',
        description: 'Proposta em análise',
        color: '#45B7D1',
        position: 3
      },
      'negotiation' => {
        name: 'Em Negociação',
        description: 'Negociação em andamento',
        color: '#96CEB4',
        position: 4
      },
      'won' => {
        name: 'Ganho',
        description: 'Venda realizada',
        color: '#2ECC71',
        position: 5
      },
      'lost' => {
        name: 'Perdido',
        description: 'Oportunidade perdida',
        color: '#E74C3C',
        position: 6
      }
    }
  )

  # Criando alguns itens de exemplo no kanban
  KanbanItem.create!(
    account_id: account.id,
    funnel_id: sales_funnel.id,
    funnel_stage: 'lead',
    position: 1,
    item_details: {
      title: 'Empresa ABC Ltda',
      description: 'Interessados em 50 licenças',
      priority: 'high',
      value: 50000
    }
  )

  KanbanItem.create!(
    account_id: account.id,
    funnel_id: sales_funnel.id,
    funnel_stage: 'contact',
    position: 1,
    item_details: {
      title: 'XYZ Tecnologia',
      description: 'Reunião inicial agendada',
      priority: 'medium',
      value: 25000
    }
  )

  KanbanItem.create!(
    account_id: account.id,
    funnel_id: sales_funnel.id,
    funnel_stage: 'proposal',
    position: 1,
    item_details: {
      title: 'Tech Solutions SA',
      description: 'Proposta enviada - aguardando feedback',
      priority: 'high',
      value: 75000
    }
  )

  # Criando 1000 itens de Kanban no Funil de Vendas
  stages = sales_funnel.stages.keys
  agent = user # Usando o usuário criado anteriormente
  currency_brl = { code: 'BRL', locale: 'pt-BR', symbol: 'R$' }

  # Serializar dados do agente uma vez, já que é o mesmo para todos
  serialized_agent = {
    id: agent.id,
    name: agent.name,
    email: agent.email,
    avatar_url: agent.avatar_url,
    availability_status: agent.availability_status
  }

  1000.times do |i|
    item_value = rand(1000..100000)
    stage = stages.sample
    
    # Criar uma atividade inicial de mudança de estágio
    initial_activity = {
      id: Time.current.to_i + i, # ID único baseado no timestamp
      type: 'stage_changed',
      user: {
        id: agent.id,
        name: agent.name,
        avatar_url: agent.avatar_url
      },
      details: {
        user: {
          id: agent.id,
          name: agent.name,
          avatar_url: agent.avatar_url
        },
        new_stage: stage,
        old_stage: nil
      },
      created_at: Time.current.iso8601
    }

    # Estrutura completa do item_details seguindo o padrão do frontend
    item_details = {
      title: "Oportunidade #{i + 1}",
      description: "Descrição detalhada da oportunidade de negócio #{i + 1}",
      priority: ['low', 'medium', 'high', 'urgent'].sample,
      value: item_value,
      agent_id: agent.id,
      agent: serialized_agent,
      currency: currency_brl,
      offers: [
        { 
          value: item_value * 0.8, 
          currency: currency_brl, 
          description: "Oferta inicial" 
        },
        { 
          value: item_value, 
          currency: currency_brl, 
          description: "Oferta padrão" 
        }
      ],
      deadline_at: (Time.current + rand(7..90).days).iso8601,
      scheduling_type: 'deadline',
      activities: [initial_activity]
    }

    # Se o item estiver associado à conversa existente
    if i == 0 # Apenas para o primeiro item, como exemplo
      item_details.merge!(
        conversation_id: conversation.id,
        conversation: {
          id: conversation.id,
          uuid: conversation.uuid,
          inbox: {
            id: conversation.inbox.id,
            name: conversation.inbox.name,
            channel_type: conversation.inbox.channel_type
          },
          status: conversation.status,
          contact: {
            id: conversation.contact.id,
            name: conversation.contact.name,
            email: conversation.contact.email,
            thumbnail: conversation.contact.avatar_url,
            phone_number: conversation.contact.phone_number,
            additional_attributes: conversation.contact.additional_attributes
          },
          team_id: conversation.team_id,
          assignee: serialized_agent,
          inbox_id: conversation.inbox_id,
          priority: conversation.priority,
          account_id: conversation.account_id,
          created_at: conversation.created_at.iso8601,
          display_id: conversation.display_id,
          label_list: conversation.cached_label_list_array,
          updated_at: conversation.updated_at.iso8601,
          campaign_id: conversation.campaign_id,
          unread_count: conversation.unread_messages.count,
          snoozed_until: conversation.snoozed_until,
          waiting_since: conversation.waiting_since,
          messages_count: conversation.messages.count,
          last_activity_at: conversation.last_activity_at,
          custom_attributes: conversation.custom_attributes,
          additional_attributes: conversation.additional_attributes,
          first_reply_created_at: conversation.first_reply_created_at
        }
      )
    end

    KanbanItem.create!(
      account_id: account.id,
      funnel_id: sales_funnel.id,
      funnel_stage: stage,
      position: i + 1,
      conversation_display_id: (i == 0 ? conversation.display_id : nil),
      item_details: item_details
    )
  end

  # Criando um funil de suporte
  support_funnel = Funnel.create!(
    account_id: account.id,
    name: 'Funil de Suporte',
    description: 'Funil para gestão de tickets de suporte',
    active: true,
    stages: {
      'new' => {
        name: 'Novo',
        description: 'Tickets recém-criados',
        color: '#3498DB',
        position: 1
      },
      'in_progress' => {
        name: 'Em Andamento',
        description: 'Tickets sendo atendidos',
        color: '#F1C40F',
        position: 2
      },
      'waiting' => {
        name: 'Aguardando Cliente',
        description: 'Esperando resposta do cliente',
        color: '#E67E22',
        position: 3
      },
      'resolved' => {
        name: 'Resolvido',
        description: 'Tickets solucionados',
        color: '#2ECC71',
        position: 4
      }
    }
  )
end
