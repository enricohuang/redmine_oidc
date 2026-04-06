require File.expand_path('test/test_helper', Dir.pwd)

class RedmineOidcAutoLoginTest < Redmine::IntegrationTest
  def setup
    super
    Setting.plugin_redmine_oidc = {
      'issuer_url' => 'http://issuer.example',
      'client_identifier' => 'redmine-oidc',
      'client_secret' => 'redmine-secret',
      'scopes' => 'openid email profile',
      'button_label' => 'Sign in with OIDC',
      'oidc_auto_login' => '1',
      'oidc_primary_login' => '0',
      'auto_registration' => '0',
      'email_matching' => '1'
    }
  end

  def test_login_page_includes_auto_login_redirect_when_enabled
    get '/login', params: {back_url: '/my/page'}

    assert_response :success
    assert_select 'meta[http-equiv=?][content=?]', 'refresh', '0;url=/oidc/authorize?back_url=%2Fmy%2Fpage'
  end

  def test_local_login_param_bypasses_auto_login_redirect
    get '/login', params: {local_login: '1'}

    assert_response :success
    assert_select 'meta[http-equiv=?]', 'refresh', 0
    assert_select 'input[name=username]'
  end

  def test_login_page_without_oidc_configuration_does_not_include_auto_redirect
    Setting.plugin_redmine_oidc = Setting.plugin_redmine_oidc.merge(
      'client_identifier' => '',
      'client_secret' => ''
    )

    get '/login'

    assert_response :success
    assert_select 'meta[http-equiv=?]', 'refresh', 0
  end
end
