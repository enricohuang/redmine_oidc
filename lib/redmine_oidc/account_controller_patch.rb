module RedmineOidc
  module AccountControllerPatch
    def self.included(base)
      base.prepend(InstanceMethods)
    end

    module InstanceMethods
      def login
        settings = Setting.plugin_redmine_oidc || {}
        local_login = params[:local_login].present?
        oidc_auto_login_ready = settings['oidc_auto_login'] == '1' &&
                                settings['issuer_url'].present? &&
                                settings['client_identifier'].present? &&
                                settings['client_secret'].present?

        if request.get? && oidc_auto_login_ready && !local_login && !User.current.logged?
          redirect_to oidc_authorize_path(back_url: params[:back_url])
        else
          super
        end
      end
    end
  end
end
