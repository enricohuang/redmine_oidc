require_relative '../../lib/redmine_oidc/oidc_client'

class OidcController < ApplicationController
  LOCAL_LOGIN_PARAM = 'local_login'.freeze

  skip_before_action :check_if_login_required, only: [:authorize, :callback]
  skip_before_action :check_password_change, only: [:authorize, :callback]
  skip_before_action :check_twofa_activation, only: [:authorize, :callback]

  def authorize
    client = RedmineOidc::OidcClient.new
    unless client.configured?
      flash[:error] = l(:oidc_error_not_configured)
      redirect_to login_redirect_path
      return
    end

    state = SecureRandom.hex(32)
    session[:oidc_state] = state
    session[:oidc_back_url] = params[:back_url] if params[:back_url].present?

    if User.current.logged?
      session[:oidc_link_mode] = true
    end

    begin
      url = client.authorization_url(
        redirect_uri: oidc_callback_url,
        state:        state
      )
      redirect_to url, allow_other_host: true
    rescue => e
      Rails.logger.error "OIDC authorize error: #{e.message}"
      flash[:error] = l(:oidc_error_provider_unreachable)
      redirect_to login_redirect_path
    end
  end

  def callback
    client = RedmineOidc::OidcClient.new

    # Verify state
    expected_state = session.delete(:oidc_state)
    if expected_state.blank? || params[:state] != expected_state
      flash[:error] = l(:oidc_error_invalid_state)
      redirect_to login_redirect_path
      return
    end

    if params[:error].present?
      flash[:error] = l(:oidc_error_provider_denied, message: params[:error_description] || params[:error])
      redirect_to login_redirect_path
      return
    end

    unless params[:code].present?
      flash[:error] = l(:oidc_error_missing_code)
      redirect_to login_redirect_path
      return
    end

    begin
      # Exchange code for tokens
      token_data = client.exchange_code(params[:code], redirect_uri: oidc_callback_url)
      access_token = token_data['access_token']
      unless access_token.present?
        flash[:error] = l(:oidc_error_no_access_token)
        redirect_to login_redirect_path
        return
      end

      # Fetch userinfo
      userinfo = client.userinfo(access_token)
      uid = userinfo['sub']
      email = userinfo['email']
      issuer = client.issuer_url

      unless uid.present?
        flash[:error] = l(:oidc_error_missing_sub)
        redirect_to login_redirect_path
        return
      end

      link_mode = session.delete(:oidc_link_mode)
      back_url = session.delete(:oidc_back_url)

      if link_mode && User.current.logged?
        handle_link_mode(User.current, issuer, uid)
      else
        handle_login_mode(client, userinfo, issuer, uid, email, back_url)
      end
    rescue => e
      Rails.logger.error "OIDC callback error: #{e.class} - #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
      flash[:error] = l(:oidc_error_callback_failed)
      redirect_to login_redirect_path
    end
  end

  def unlink
    require_login
    return unless User.current.logged?

    link = if params[:id].present?
             User.current.oidc_user_links.find_by(id: params[:id])
           else
             User.current.oidc_user_links.first
           end
    if link
      link.destroy
      flash[:notice] = l(:oidc_notice_unlinked)
    else
      flash[:warning] = l(:oidc_warning_not_linked)
    end
    redirect_to my_account_path
  end

  def admin_unlink
    unless User.current.admin?
      deny_access
      return
    end

    link = OidcUserLink.find_by(id: params[:id])
    if link
      target_user = link.user
      link.destroy
      flash[:notice] = l(:oidc_admin_notice_unlinked)
      redirect_to edit_user_path(target_user)
    else
      flash[:warning] = l(:oidc_warning_not_linked)
      redirect_to users_path
    end
  end

  private

  def handle_link_mode(user, issuer, uid)
    existing = OidcUserLink.find_by(issuer: issuer, uid: uid)
    if existing
      if existing.user_id == user.id
        flash[:notice] = l(:oidc_notice_already_linked)
      else
        flash[:error] = l(:oidc_error_uid_taken)
      end
    else
      OidcUserLink.create!(user: user, issuer: issuer, uid: uid)
      flash[:notice] = l(:oidc_notice_linked)
    end
    redirect_to my_account_path
  end

  def handle_login_mode(client, userinfo, issuer, uid, email, back_url)
    settings = Setting.plugin_redmine_oidc || {}

    # 1. Look up by issuer + uid link
    link = OidcUserLink.find_by(issuer: issuer, uid: uid)
    user = link&.user

    # 2. Email fallback
    if user.nil? && email.present? && settings['email_matching'] == '1'
      user = User.find_by_mail(email)
      if user
        # Auto-create link for matched user
        OidcUserLink.create(user: user, issuer: issuer, uid: uid)
      end
    end

    # 3. Auto-registration
    if user.nil? && settings['auto_registration'] == '1' && email.present?
      user = auto_register_user(userinfo, issuer, uid, email)
      unless user&.persisted?
        flash[:error] = l(:oidc_error_auto_register_failed)
        redirect_to login_redirect_path
        return
      end
    end

    if user.nil?
      flash[:error] = l(:oidc_error_no_matching_user)
      redirect_to login_redirect_path
      return
    end

    unless user.active?
      flash[:error] = l(:oidc_error_user_inactive)
      redirect_to login_redirect_path
      return
    end

    # Log in the user
    params[:back_url] = back_url if back_url.present?
    successful_authentication(user)
  end

  def auto_register_user(userinfo, issuer, uid, email)
    login = derive_login(email)
    firstname = userinfo['given_name'].presence || userinfo['name'].to_s.split(' ', 2).first.presence || login
    lastname = userinfo['family_name'].presence || userinfo['name'].to_s.split(' ', 2).last.presence || '-'

    user = User.new(
      login:     login,
      firstname: firstname,
      lastname:  lastname,
      mail:      email,
      language:  Setting.default_language
    )
    user.random_password
    user.activate
    user.last_login_on = Time.now

    if user.save
      OidcUserLink.create(user: user, issuer: issuer, uid: uid)
      user
    else
      Rails.logger.error "OIDC auto-registration failed for #{email}: #{user.errors.full_messages.join(', ')}"
      nil
    end
  end

  def derive_login(email)
    base = email.split('@').first.to_s
    base = base.gsub(/[^a-z0-9_\-@.]/i, '')
    base = 'user' if base.blank?

    limit = User::LOGIN_LENGTH_LIMIT
    base = base[0, limit]

    login = base
    counter = 1
    while User.find_by_login(login)
      suffix = counter.to_s
      login = "#{base[0, limit - suffix.length]}#{suffix}"
      counter += 1
    end
    login
  end

  def successful_authentication(user)
    logger.info "OIDC: Successful authentication for '#{user.login}' from #{request.remote_ip}" if logger
    user.update_last_login_on!
    self.logged_user = user
    update_sudo_timestamp!
    call_hook(:controller_account_success_authentication_after, {user: user})
    redirect_back_or_default my_page_path
  end

  def login_redirect_path
    redirect_params = {}
    redirect_params[LOCAL_LOGIN_PARAM] = '1' if auto_login_enabled?
    redirect_params[:back_url] = session[:oidc_back_url] if session[:oidc_back_url].present?
    signin_path(redirect_params)
  end

  def auto_login_enabled?
    settings = Setting.plugin_redmine_oidc || {}
    settings['oidc_auto_login'] == '1'
  end
end
