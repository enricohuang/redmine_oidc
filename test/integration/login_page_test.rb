require File.expand_path('test/test_helper', Dir.pwd)

class RedmineOidcLoginPageTest < Redmine::IntegrationTest
  def plugin_settings(overrides = {})
    {
      'issuer_url' => 'http://issuer.example',
      'client_identifier' => 'redmine-oidc',
      'client_secret' => 'redmine-secret',
      'scopes' => 'openid email profile',
      'button_label' => 'Sign in with OIDC',
      'oidc_primary_login' => '0',
      'auto_registration' => '0',
      'email_matching' => '1'
    }.merge(overrides)
  end

  def test_login_page_renders_secondary_oidc_button_by_default
    Setting.plugin_redmine_oidc = plugin_settings

    get '/login'

    assert_response :success
    assert_select '.oidc-login-separator span', text: 'or'
    assert_select '.oidc-login-button', text: 'Sign in with OIDC'
    assert_select 'details.oidc-local-login-fallback', 0
  end

  def test_login_page_can_make_oidc_primary_with_local_fallback_form
    Setting.plugin_redmine_oidc = plugin_settings('oidc_primary_login' => '1')

    get '/login'

    assert_response :success
    assert_select '.oidc-login-panel--primary .oidc-login-button', text: 'Sign in with OIDC'
    assert_select 'details.oidc-local-login-fallback summary', text: 'Use local account instead'
    assert_select 'details.oidc-local-login-fallback input[name=username]'
    assert_select 'details.oidc-local-login-fallback input[name=password]'
    assert_includes response.body, '#content > #login-form'
    assert_includes response.body, 'display: none;'
  end
end
