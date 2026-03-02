# config/initializers/stacklab_initializer.rb

# Este inicializador garante que a tentativa de carregar o Stacklab::LicensingService
# ocorra durante a inicialização do aplicativo Rails.
# Isso é útil para registrar quaisquer erros críticos de carregamento (como falha ao encontrar
# o arquivo de serviço ou dependências ausentes) o mais cedo possível no console
# ou nos logs, conforme definido em ChatwootApp.ensure_stacklab_service_loaded.

if defined?(ChatwootApp) && ChatwootApp.respond_to?(:ensure_stacklab_service_loaded, true) # O segundo argumento `true` verifica métodos privados/protegidos também
  Rails.application.config.after_initialize do
    # Chamamos ensure_stacklab_service_loaded para que qualquer log de erro de carregamento
    # do serviço de licença seja disparado durante a inicialização.
    ChatwootApp.send(:ensure_stacklab_service_loaded)
    
    # Opcionalmente, você pode querer verificar o status da licença aqui também
    # e logar alguma informação, mas a principal função deste inicializador
    # é garantir que o `require_dependency` dentro de `ensure_stacklab_service_loaded` seja tentado.
    # Exemplo de log adicional (opcional):
    # if ChatwootApp.stacklab.service_available?
    #   Rails.logger.info "StackLab Licensing Service carregado. Plano atual: #{ChatwootApp.stacklab.plan}"
    # else
    #   Rails.logger.warn "StackLab Licensing Service não pôde ser carregado ou está indisponível."
    # end
  end
else
end 