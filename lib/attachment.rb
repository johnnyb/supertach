## NOTES - should thumbnails have database records?
## NOTES - need to add 'storage' field, and a method to migrate storage, and a default storage, and a per-relationship default storage

# This is the main class used in Supertach.  The attachment class is poly-polymorphic, 
# meaning that not only can it be attached to any class, but it can also be attached
# multiple times.
#
# Relationships:
#   attachable - this is the object that the attachment is attached to
#
# Scopes:
#   position_order - order by the "position" field
#   reverse_position_order - reverse of the above
#   active - there is an "active" flag, this selects attachments where the "active" flag is set.  You can choose to make use of this or not.
#   public - this is not yet functional
class Attachment < ActiveRecord::Base
	belongs_to :attachable, :polymorphic => true
	scope :position_order, :order => "position, id"
	scope :reverse_position_order, :order => "position DESC, id DESC"
	scope :active, :conditions => { :active => true }
	scope :public, :conditions => { :public => false }
	serialize :representations

	before_create do |rec|
		# Auto-set position
		if rec["position"].nil?
			att = Attachment.reverse_position_order.find(:first, :conditions => { :attachable_id => rec.attachable_id, :attachable_type => rec.attachable_type, :relationship => rec.relationship })
			if att.nil?
				rec["position"] = 0
			else
				rec["position"] = (att.position || 0) + 1
			end
		end

		# Set the representations
		rec["representations"] ||= {}
	end

	before_save do |rec|
		if rec.storage_system_name.nil?
			rec["storage_system_name"] = Attachment.default_storage_system_name
		end
	end

	after_save do |rec|
		unless rec.data_to_save.nil?
			storage_handler.store(rec.storage_key, rec.data_to_save, {:public => rec.public?, :content_type => rec.content_type})
			rec.data_to_save = nil
		end
	end

	before_destroy do |rec|
		storage_handler.destroy(rec.storage_key)
	end

	##### Basic Functions ####

	# FIXME - unimplemented - whether this is public or private
	def public?
		!private?
	end

	##### FILE STORAGE FUNCTIONS ####

	# Access any data ready to save out
	def data_to_save
		@data_to_save
	end

	# Set the data to save out - if you want content_type or filename set, then those should be set separately.
	# This should be an already-opened file, ready to have read() called on it.
	def data_to_save=(val)
		@data_to_save = val
	end

	# Sets the filename, content_type, and file data from an uploaded file field
	def uploaded_data=(d)
		# FIXME - should have ability to autodetect content_type
		self.content_type = d.content_type
		self.filename = Attachment.sanitize_filename(d.original_filename)
		self.data_to_save = d
	end

	# Migrates the file to a different system store, with new_store being the system name of the new storage mechanism
	def migrate_storage!(new_store)
		new_store = new_store.to_s

		tmpf = storage_handler.tempfile_for(storage_key)
		tmpf.open
		self.storage_system_name = new_store
		self.data_to_save = tmpf
		self.save!

		#FIXME - either migrate or destroy the representations
	end

	# Clears every representation in the database
	# NOTE - if you have a lot of attachments, this is a bad idea
	def self.clear_all_representations!
		Attachment.all.each do |att|
			att.clear_representations!
		end
	end

	# Remove all representations of this file
	def clear_representations!
		unless representations.nil?
			representations.keys.each do |k|
				key = k.split("/")
				storage_handler.destroy(key)
			end
		end

		self.representations = {}
		self.save!
	end

	# Get the storage key for the file (used by the storage handlers)
	def storage_key
		return storage_key_base + [filename]
	end

	def storage_key_base
		min = (id % 10000).to_s
		maj = (id / 10000).to_s
		[maj, min]
	end

	#### METADATA FUNCTIONS ####

	# if the content_type is "image/jpeg" this is "image"
	def content_type_major
		content_type.split(/\//).first
	end

	# if the content_type is "image/jpeg" this is "jpeg"
	def content_type_minor
		content_type.split(/\//).last
	end

	# The storage handler used by this class
	def storage_handler
		@@storage_handlers[storage_system_name]
	end

	# The extension of the file
	def extension
		filename[(filename.rindex(".")+1)..-1]
	end

	# The filename without the extension
	def filename_no_extension
		extidx = filename.rindex(".")
		filename[0..(extidx - 1)]
	end

	#### REPRESENTATION / THUMBNAILING FUNCTIONS ####

	# Returns a public url for this
	def public_url
		storage_handler.public_url_for(storage_key)
	end

	# Generates a thumnail representation.  Defaults to a jpg, set :extension if you want something else.
	# :width sets the width
	def thumbnail!(opts = {})
		opts[:extension] ||= "jpg"
		representation_public_url!(:image, opts)
	end

	# NOTE - locking will not work properly without being called from a transaction
	# This either returns a public url for a representation or it generates one.
	# Returns nil if nothing could be generated.  rtype is the type of representation,
	# and opts are the options to hand to the representation handler.
	#
	# Returns a representation of type rtype according to the given options.
	# One option is :extension, which is used to generate the final filename.  Without
	# :extension, it assumes that the final extension is the same extension as the existing
	# file.
	def representation_public_url!(rtype, opts = {})
		ext = opts.delete(:extension)
		if ext.nil?
			ext = extension
		end

		# Create a representation key
		repkeytrailer = "#{filename_no_extension}_#{rtype}_#{opts.to_a.flatten.join("_")}.#{ext}"
		repkey = self.storage_key_base + [repkeytrailer]

		# The joined key will be used in our representations hash
		repkey_joined = repkey.join("/")

		# Return the representation URL if we already have it
		return storage_handler.public_url_for(repkey) if representations.include?(repkey_joined)

		if @@use_locking
			self.save! if self.new_record? #Make sure a record exists
			self.lock! #Lock the record
			
			# Check the condition again (lock has reloaded the record)
			return storage_handler.public_url_for(repkey) if representations.include?(repkey_joined)
		end
		
		# Go through each representation handlers for the representation type, and see if any of them
		# can handle the request	
		(@@representation_handlers[rtype] || []).each do |rh|
			# Grab a representation
			val_fh = rh.create_representation_file(self, rtype, ext, opts)

			# Valid?
			unless val_fh.nil?
				# Store the representation
				storage_handler.store(repkey, val_fh, { :public => self.public? })  #NOTE - should I set content_type in the options?
				# Grab the URL for the representation
				val = storage_handler.public_url_for(repkey)

				# Save the representation information
				reps = self.representations
				reps[repkey_joined] = val
				self.representations = reps
				self.save!

				# Return our new representation
				return val
			end
		end

		# If we didn't find and couldn't generate a representation, return nil
		return nil
	end

	#### UTILITY FUNCTIONS ####

	# In the future this can be used to auto-detect content_types
	def self.default_content_type_for_extension(ext)
		"FIXME"
	end

	# Removes all nastiness from filenames
	def self.sanitize_filename(fname)
		fname = "file.dat" if fname.blank?

		# Remove any preceding path
		val = fname.split("/").last
		
		# Remove bad characters
		val = val.gsub(/[^a-zA-Z0-9_\.]/, "_")

		# Force an extension
		extoffset = val.rindex(".")
		if extoffset == nil
			val = val + ".dat"
		elsif extoffset == val.size - 1
			val = val + "dat"
		end

		# Force lower-case
		val = val.downcase

		return val
	end

	#### CLASS/HANDLER SETUP ####

	@@use_locking = true
	# Experimental and untested
	def self.use_locking=(val)
		@@use_locking = val
	end

	# Representation handlers get called with create_representation_file(att, rtype, ext, opts) and should return nil if it can't be performed
	@@representation_handlers = {}
	def self.register_representation_handler(rtype, rhandler)
		@@representation_handlers[rtype] ||= []
		@@representation_handlers[rtype].push(rhandler)
	end

	# Remove all representation handlers
	def self.clear_representation_handlers
		@@representation_handlers = {}
	end

	# Storage handlers.  These must respond to the following: store(key, fdata, opts={}), destroy(key), tempfile_for(key), public_url_for(key, opts={})
	@@storage_handlers = {}
	def self.register_storage_handler(storname, stor)
		@@storage_handlers[storname.to_s] = stor
	end

	# Remove storage handlers
	def self.clear_storage_handlers
		@@storage_handlers = {}
	end


	@@default_store = nil
	def self.default_storage_system_name
		if @@default_store.nil?
			return @@storage_handlers.first[0]
		else
			return @@storage_handlers[dstore]
		end
	end

	# Sets the default store to be used
	def self.default_storage_system_name=(val)
		@@default_store = val
	end
end
