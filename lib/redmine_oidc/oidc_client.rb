require 'net/http'
require 'json'
require 'uri'

module RedmineOidc
  class OidcClient
    TIMEOUT = 10

    attr_reader :issuer_url, :client_id, :client_secret, :scopes

    def initialize
      settings = Setting.plugin_redmine_oidc || {}
      @issuer_url    = settings['issuer_url'].to_s.chomp('/')
      @client_id     = settings['client_identifier'].to_s
      @client_secret = settings['client_secret'].to_s
      @scopes        = settings['scopes'].to_s.presence || 'openid email profile'
    end

    def configured?
      @issuer_url.present? && @client_id.present? && @client_secret.present?
    end

    def discovery
      @discovery ||= fetch_json("#{@issuer_url}/.well-known/openid-configuration")
    end

    def authorization_url(redirect_uri:, state:)
      params = {
        response_type: 'code',
        client_id:     @client_id,
        redirect_uri:  redirect_uri,
        scope:         @scopes,
        state:         state
      }
      "#{discovery['authorization_endpoint']}?#{URI.encode_www_form(params)}"
    end

    def exchange_code(code, redirect_uri:)
      uri = URI.parse(discovery['token_endpoint'])
      body = {
        grant_type:    'authorization_code',
        code:          code,
        redirect_uri:  redirect_uri,
        client_id:     @client_id,
        client_secret: @client_secret
      }
      response = post_request(uri, body)
      JSON.parse(response.body)
    end

    def userinfo(access_token)
      uri = URI.parse(discovery['userinfo_endpoint'])
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{access_token}"
      response = execute_request(uri, request)
      JSON.parse(response.body)
    end

    private

    def fetch_json(url)
      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri)
      request['Accept'] = 'application/json'
      response = execute_request(uri, request)
      JSON.parse(response.body)
    end

    def post_request(uri, body)
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/x-www-form-urlencoded'
      request['Accept'] = 'application/json'
      request.body = URI.encode_www_form(body)
      execute_request(uri, request)
    end

    def execute_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      http.request(request)
    end
  end
end
