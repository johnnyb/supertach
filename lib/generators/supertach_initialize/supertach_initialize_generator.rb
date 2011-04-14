require "rails/generators"
require "rails/generators/base"
require "rails/generators/migration"
class SupertachInitializeGenerator < Rails::Generators::Base
	include Rails::Generators::Migration
	source_root File.expand_path("../templates", __FILE__)

	def create_migration_files
		[
			"20110413105335_create_attachments.rb"
		].each do |f|
			template "migrations/#{f}", "db/migrate/#{f}"
		end
	end
end
