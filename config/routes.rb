get  'oidc/authorize', to: 'oidc#authorize', as: :oidc_authorize
get  'oidc/callback',  to: 'oidc#callback',  as: :oidc_callback
post 'oidc/unlink',    to: 'oidc#unlink',    as: :oidc_unlink
post 'oidc/admin_unlink/:id', to: 'oidc#admin_unlink', as: :oidc_admin_unlink
