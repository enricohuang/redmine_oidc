class CreateOidcUserLinks < ActiveRecord::Migration[5.2]
  def change
    create_table :oidc_user_links do |t|
      t.integer :user_id, null: false
      t.string :issuer,   null: false
      t.string :uid,      null: false
      t.timestamps null: false
    end
    add_index :oidc_user_links, [:issuer, :uid], unique: true
    add_index :oidc_user_links, :user_id
  end
end
