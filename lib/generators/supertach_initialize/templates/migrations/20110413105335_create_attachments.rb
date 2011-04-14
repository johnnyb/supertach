class CreateAttachments < ActiveRecord::Migration
  def self.up
    create_table :attachments do |t|
      # Connect thumbnails to attachments
      t.integer :parent_id
      t.string :representation_key

      # Basic Description
      t.string :name
      t.text :description
      t.text :url
      t.text :extra_info

      # Access Information
      t.string :storage_system_name # where is it stored?
      t.boolean :active
      t.boolean :private, :default => false
     
      # Linking Stuff
      t.integer :attachable_id
      t.string :attachable_type
      t.string :relationship
      t.integer :position 

      # File-handling stuff
      t.string :filename
      t.string :content_type
      t.integer :filesize

      # Generic field to throw representation info - may not use it in the future
      t.text :representations

      t.timestamps
    end
  end

  def self.down
    drop_table :attachments
  end
end
