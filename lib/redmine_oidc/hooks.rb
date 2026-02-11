module RedmineOidc
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_account_login_bottom,
              partial: 'hooks/redmine_oidc/login_bottom'
    render_on :view_my_account,
              partial: 'hooks/redmine_oidc/my_account'
    render_on :view_layouts_base_html_head,
              partial: 'hooks/redmine_oidc/html_head'
    render_on :view_users_form,
              partial: 'hooks/redmine_oidc/users_form'
  end
end
