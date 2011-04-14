require "supertach"
require "attachment" # Moved to lib so that ActiveSupport won't try to reload it and break it

Attachment.register_representation_handler(:image, ThumbnailRepresentation.new)
Attachment.register_storage_handler(:filesystem, FilesystemStorageHandler.new("#{Rails.root}/public/images/attachments", "/images/attachments"))
Attachment.use_locking = false
