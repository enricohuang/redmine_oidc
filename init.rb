require_relative 'lib/redmine_oidc/hooks'

Redmine::Plugin.register :redmine_oidc do
  name 'Redmine OIDC'
  author 'Redmine OIDC Plugin'
  description 'OpenID Connect single sign-on for Redmine. Works with Google, Microsoft, and any OIDC-compliant provider.'
  version '1.0.0'
  url 'https://github.com/enricohuang/redmine_oidc'

  settings default: {
    'client_identifier' => '',
    'client_secret'     => '',
    'issuer_url'        => '',
    'scopes'            => 'openid email profile',
    'button_label'      => 'Sign in with OpenID Connect',
    'oidc_auto_login'   => '0',
    'oidc_primary_login' => '0',
    'auto_registration' => '0',
    'email_matching'    => '1'
  }, partial: 'settings/redmine_oidc_settings'
end

unless User.reflect_on_association(:oidc_user_links)
  User.class_eval do
    has_many :oidc_user_links, dependent: :destroy
  end
end

Rails.application.config.after_initialize do
  require_relative 'lib/redmine_oidc/account_controller_patch'
  AccountController.include(RedmineOidc::AccountControllerPatch)
end
