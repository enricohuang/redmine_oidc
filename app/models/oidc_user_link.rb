class OidcUserLink < ActiveRecord::Base
  belongs_to :user

  validates :issuer, presence: true
  validates :uid, presence: true, uniqueness: {scope: :issuer}
  validates :user_id, presence: true
end
