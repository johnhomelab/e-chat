class SuperAdmin::ScriptGalleryController < SuperAdmin::ApplicationController
  REPO_OWNER = 'StackLab-Digital'
  REPO_NAME = 'ModulosKanban'
  CONTENT_PATH = 'examples'
  API_BASE = 'https://api.github.com'
  DEFAULT_BRANCH = 'master'

  def index
    @scripts = fetch_scripts_from_github
  end

  def show
    @script_name = params[:script_name]
    # Garantir que o script_name tenha a extensão .html
    unless @script_name.end_with?('.html')
      @script_name = "#{@script_name}.html"
    end
    
    @script_content = fetch_script_content(@script_name)
    @script_preview_url = "https://github.com/#{REPO_OWNER}/#{REPO_NAME}/blob/#{DEFAULT_BRANCH}/#{CONTENT_PATH}/#{@script_name}"
  end
  
  # Método para obter o conteúdo raw diretamente
  def raw_content
    script_name = params[:script_name]
    unless script_name.end_with?('.html')
      script_name = "#{script_name}.html"
    end
    
    content = fetch_script_content(script_name)
    render plain: content
  end

  private

  def fetch_scripts_from_github
    require 'net/http'
    require 'json'

    # Endpoint para listar conteúdo de diretório conforme documentação
    api_url = "#{API_BASE}/repos/#{REPO_OWNER}/#{REPO_NAME}/contents/#{CONTENT_PATH}?ref=#{DEFAULT_BRANCH}"
    
    response = make_github_request(api_url)
    
    if response.is_a?(Net::HTTPSuccess)
      files = JSON.parse(response.body)
      files.select { |file| file['type'] == 'file' && file['name'].end_with?('.html') }
    else
      Rails.logger.error("GitHub API error: #{response.code} - #{response.message}")
      []
    end
  rescue StandardError => e
    Rails.logger.error("Error fetching scripts from GitHub: #{e.message}")
    []
  end

  def fetch_script_content(script_name)
    require 'net/http'

    # Endpoint para obter conteúdo de arquivo conforme documentação
    api_url = "#{API_BASE}/repos/#{REPO_OWNER}/#{REPO_NAME}/contents/#{CONTENT_PATH}/#{script_name}?ref=#{DEFAULT_BRANCH}"
    
    response = make_github_request(api_url, raw_content: true)
    
    if response.is_a?(Net::HTTPSuccess)
      # A resposta já vem como conteúdo raw devido ao header Accept
      content = response.body
      content = content.force_encoding('UTF-8')
      
      # Se não for válido UTF-8, tenta converter de ISO-8859-1
      unless content.valid_encoding?
        content = response.body.force_encoding('ISO-8859-1').encode('UTF-8')
      end
      
      content
    else
      "// Erro: O GitHub não retornou o conteúdo do arquivo.\n// Código HTTP: #{response.code}\n// Mensagem: #{response.message}"
    end
  rescue StandardError => e
    Rails.logger.error("Error fetching script content from GitHub: #{e.message}")
    "// Erro ao carregar o script: #{e.message}"
  end
  
  def make_github_request(url, raw_content: false)
    uri = URI(url)
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 10
    
    # Configurar para seguir redirecionamentos automaticamente
    http.max_retries = 3
    
    request = Net::HTTP::Get.new(uri.request_uri)
    request["User-Agent"] = "Chatwoot-Application"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    
    if raw_content
      request["Accept"] = "application/vnd.github.raw+json"
    else
      request["Accept"] = "application/vnd.github+json"
    end
    
    response = http.request(request)
    
    # Processar redirecionamentos manualmente se necessário
    if response.is_a?(Net::HTTPRedirection)
      Rails.logger.info("Redirecionando para: #{response['location']}")
      redirect_uri = URI(response['location'])
      redirect_http = Net::HTTP.new(redirect_uri.host, redirect_uri.port)
      redirect_http.use_ssl = (redirect_uri.scheme == 'https')
      redirect_request = Net::HTTP::Get.new(redirect_uri.request_uri)
      redirect_request["User-Agent"] = "Chatwoot-Application"
      redirect_request["Accept"] = request["Accept"]
      redirect_request["X-GitHub-Api-Version"] = "2022-11-28"
      
      response = redirect_http.request(redirect_request)
    end
    
    response
  end
end 