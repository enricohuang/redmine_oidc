require File.expand_path('test/test_helper', Dir.pwd)

class OidcControllerTest < Redmine::ControllerTest
  tests OidcController

  def setup
    super
    User.current = nil
    Setting.plugin_redmine_oidc = {
      'issuer_url' => 'http://issuer.example',
      'client_identifier' => 'redmine-oidc',
      'client_secret' => 'redmine-secret',
      'scopes' => 'openid email profile',
      'button_label' => 'Sign in with OIDC',
      'oidc_primary_login' => '0',
      'auto_registration' => '0',
      'email_matching' => '1'
    }
    OidcUserLink.delete_all
  end

  def test_callback_updates_last_login_and_sudo_timestamp_for_oidc_login
    user = User.find(2)
    user.update_column(:last_login_on, nil)

    RedmineOidc::OidcClient.any_instance.stubs(:exchange_code).returns('access_token' => 'access-token')
    RedmineOidc::OidcClient.any_instance.stubs(:userinfo).returns(
      'sub' => 'oidc-subject',
      'email' => user.mail
    )
    RedmineOidc::OidcClient.any_instance.stubs(:issuer_url).returns('http://issuer.example')

    @request.session[:oidc_state] = 'expected-state'

    get :callback, params: {code: 'auth-code', state: 'expected-state'}

    assert_redirected_to '/my/page'
    assert_equal user.id, @request.session[:user_id]
    assert_not_nil user.reload.last_login_on
    assert_not_nil @request.session[:sudo_timestamp]

    link = OidcUserLink.find_by(user_id: user.id)
    assert_equal 'http://issuer.example', link.issuer
    assert_equal 'oidc-subject', link.uid
  end
end
