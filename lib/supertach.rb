require "fileutils"
class FilesystemStorageHandler
	def initialize(path, pubpath)
		@path = path
		@public_path = pubpath
	end

	def store(key, fdata, opts = {})
		block_size = opts[:blocksize] || 1024
		FileUtils.mkdir_p(dirname_for(key))
		fh = File.open(filename_for(key), "wb")
		#IO.copy_stream(fdata, fh) - apparently this is only for newer ruby versions
		while(str = fdata.read(block_size))
			fh.write(str)
		end

		fh.close
	end

	def storage_system_name=(val)
		@storage_system_name = val	
	end

	def storage_system_name
		@storage_system_name
	end

	def destroy(key)
		#FIXME - destroy file
	end

	def tempfile_for(key)
		fname = key.last
		extidx = fname.rindex(".")
		ext = fname[(extidx+1)..-1]
	
		tmp_f = Tempfile.new(["tmpf", ".#{ext}"])
		tmp_f.close

		FileUtils.cp(filename_for(key), tmp_f.path)

		return tmp_f
	end

	def public_url_for(key, opts = {})
		"#{@public_path}/#{relative_filename_for(key)}"
	end

	private
	def relative_filename_for(key)
		key.join("/")
	end

	def filename_for(key)
		"#{@path}/#{relative_filename_for(key)}"
	end

	def dirname_for(key)
		filename_for(key[0..-2])
	end
end

class ThumbnailRepresentation
	def create_representation_file(att, rtype, ext, opts = {})
		s = att.storage_handler
		orig_tmpfile = s.tempfile_for(att.storage_key)
		orig_fname = orig_tmpfile.path

		tmp_f = Tempfile.new(["repr", ".#{ext}"])
		tmp_f.close

		discard = `convert #{orig_fname} -resize #{opts[:width]}x #{tmp_f.path} 2>&1`
		RAILS_DEFAULT_LOGGER.warn("output: #{discard}")

		tmp_f.open

		return tmp_f
	end

	def representation(att, rtype, ext, repkey, opts = {})
		s.store(repkey, tmp_f)
	end
end

module Supertach
	module ClassMethods
		def has_one_attachment(relationship, options = {})
			has_one relationship, :as => :attachable, :class_name => "Attachment", :conditions => {:relationship => relationship.to_s }, :dependent => :destroy

			define_method("attach_#{relationship}") do |file_field|
				unless file_field.nil?
					if file_field.size > 0
						self.send("create_#{relationship}", :uploaded_data => file_field, :storage_system_name => options[:storage_system_name])
					end
				end
			end
			define_method("#{relationship}_upload=") do |file_field|
				self.send("attach_#{relationship}", file_field)
			end
		end

		def has_many_attachments(relationship, options = {})
			has_many relationship, :as => :attachable, :class_name => "Attachment", :conditions => { :relationship => relationship.to_s }, :dependent => :destroy, :order => "position, id"
			define_method("#{relationship}_files=") do |flds|
				flds.keys.each do |k|
					if k.include?("new")
						self.send(relationship).build(:uploaded_data => flds[k])
					else
						self.send(relationship).find(k).uploaded_data = flds[k]
					end
				end
			end
		end
	end

	def self.included(base)
		base.extend(ClassMethods)
	end
end

ActiveRecord::Base.send(:include, Supertach)
