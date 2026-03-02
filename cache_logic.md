# Sistema de Cache do Chatwoot

Este documento detalha a implementação do sistema de cache no Chatwoot, abrangendo tanto o backend (Rails) quanto o frontend.

## Estrutura de Cache

O Chatwoot utiliza dois tipos principais de cache:

### 1. Cache do Rails
```ruby
# config/environments/development.rb
config.cache_store = :memory_store  # Em desenvolvimento
config.cache_store = :null_store    # Em teste

# config/environments/production.rb
# config.cache_store = :mem_cache_store  # Em produção (comentado)
```

### 2. Cache Redis (Redis::Alfred)
- Implementação personalizada usando Redis para cache distribuído
- Usado principalmente para cache de invalidação e dados em tempo real

## Sistema de Cache de Modelos

O sistema implementa um mecanismo sofisticado de cache através do módulo `CacheKeys`:

```ruby
module CacheKeys
  CACHE_KEYS_EXPIRY = 72.hours

  included do
    class_attribute :cacheable_models
    self.cacheable_models = [Label, Inbox, Team]
  end

  def cache_keys
    keys = {}
    self.class.cacheable_models.each do |model|
      keys[model.name.underscore.to_sym] = fetch_value_for_key(id, model.name.underscore)
    end
    keys
  end
end
```

## Invalidação de Cache

O sistema usa um padrão de invalidação baseado em timestamps através do `AccountCacheRevalidator`:

```ruby
module AccountCacheRevalidator
  included do
    after_commit :update_account_cache, on: [:create, :update, :destroy]
  end

  def update_account_cache
    account.update_cache_key(self.class.name.underscore)
  end
end
```

## Helpers de Cache

O `CacheKeysHelper` fornece funções auxiliares para manipulação de chaves de cache:

```ruby
module CacheKeysHelper
  def get_prefixed_cache_key(account_id, key)
    "idb-cache-key-account-#{account_id}-#{key}"
  end

  def fetch_value_for_key(account_id, key)
    prefixed_cache_key = get_prefixed_cache_key(account_id, key)
    value_from_cache = Redis::Alfred.get(prefixed_cache_key)
    return value_from_cache if value_from_cache.present?
    '0000000000'  # epoch time zero
  end
end
```

## API de Cache

O sistema expõe as chaves de cache através de um endpoint na API:

```ruby
# app/controllers/api/v1/accounts_controller.rb
def cache_keys
  expires_in 10.seconds, public: false, stale_while_revalidate: 5.minutes
  render json: { cache_keys: cache_keys_for_account }, status: :ok
end

def cache_keys_for_account
  {
    label: fetch_value_for_key(params[:id], Label.name.underscore),
    inbox: fetch_value_for_key(params[:id], Inbox.name.underscore),
    team: fetch_value_for_key(params[:id], Team.name.underscore)
  }
end
```

## Integração Frontend-Backend

O sistema de cache é integrado com o frontend através de:

1. **Endpoint de Cache Keys**: `/api/v1/accounts/{account_id}/cache_keys`
2. **Eventos WebSocket**: Notifica o frontend sobre invalidações de cache
3. **CacheEnabledApiClient**: Cliente JavaScript que gerencia o cache no frontend

## Fluxo de Funcionamento

### 1. Inicialização
- Modelos marcados como `cacheable_models` são monitorados
- Cada modelo tem uma chave de cache associada no Redis

### 2. Atualização de Dados
- Quando um modelo é alterado (create/update/destroy)
- O `AccountCacheRevalidator` é acionado
- A chave de cache é atualizada no Redis
- Um evento de invalidação é disparado

### 3. Verificação de Cache
- Frontend solicita chaves de cache via API
- Compara com chaves locais
- Se diferentes, recarrega dados
- Se iguais, usa cache local

### 4. Expiração
- Chaves de cache expiram após 72 horas
- Cache HTTP expira em 10 segundos
- Permite revalidação em segundo plano por 5 minutos

## Benefícios

### 1. Performance
- Reduz requisições ao servidor
- Cache distribuído via Redis
- Cache local no frontend

### 2. Consistência
- Invalidação automática
- Propagação de alterações em tempo real
- Controle granular por modelo

### 3. Escalabilidade
- Cache distribuído
- Baixa latência
- Suporte a múltiplos servidores

## Conclusão

Este sistema de cache é particularmente eficiente para aplicações em tempo real como o Chatwoot, onde dados precisam ser sincronizados entre múltiplos clientes e servidores, mantendo a performance e a consistência dos dados. A combinação de cache no frontend (IndexedDB) e backend (Redis) proporciona uma experiência rápida e confiável para os usuários, enquanto mantém a complexidade do sistema gerenciável. 