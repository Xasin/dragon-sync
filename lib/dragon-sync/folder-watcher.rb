
require 'rb-inotify'

module DragonSync
	class FolderWatcher
		attr_reader :known_files
		attr_reader :commited_files

		attr_reader :latest_atime

		def initialize(folder_dir, exclude: [])
			@root = File.expand_path(folder_dir) + '/'

			@exclude_patterns = exclude
			@known_files = {}
			
			# 'Commited files' contains records of all files that
			# have been handled by the processing system.
			# If an entry of @known_files contains the equivalent atime to that
			# of the commited file entry, it has been dealt with
			@commited_files = {}

			@latest_atime = Time.at(0)

			@file_mutex = Mutex.new

			@on_file_change = nil
		end
	
		def on_file_change(&block)
			@on_file_change = block
		end

		def is_excluded?(fname)
			@exclude_patterns.each do |pattern|
				return true if File.fnmatch(pattern, fname, File::FNM_DOTMATCH);
			end

			return false
		end

		def rescan_files
			@file_mutex.synchronize do
				
				raw_find_list = `find #{@root} -type f -printf '"%p" %T@\n'`.split("\n")

				@known_files = {}

				raw_find_list.each do |file_str|
					match = /"#{Regexp.escape(@root)}([^"]+)" ([\d\.]+)/.match file_str
					next if match.nil?
					
					file_name  = match[1]
					file_atime = Time.at(match[2].to_f)

					next if is_excluded? file_name

					@known_files[file_name] = file_atime
				end

				@latest_atime = @known_files.values.max
			end

			@on_file_change&.call() unless @known_files == @commited_files
		end

		def start_inotify
			return unless @inotify_thread.nil?

			@inotify_thread = Thread.new do
				@inotify_instance = INotify::Notifier.new()
				
				@inotify_instance.watch(@root, 
					:recursive, :close_write, :move, :create, :delete) do |event|
		
					file_name = event.absolute_name.gsub(@root, '');
					
					next if is_excluded? file_name

					@file_mutex.synchronize do
						if (event.flags.include? :delete) || (event.flags.include? :move_from)
							@known_files.delete file_name
						else
							@known_files[file_name] = Time.now
						end

						@latest_atime = Time.now
					end

					@on_file_change&.call
				end

				@inotify_instance.run
			end
			
			@inotify_thread.abort_on_exception = true
		end

		def up_to_date?
			return false if @known_files.keys.sort != @commited_files.keys.sort

			@commited_files.each do |file_name, file_atime|
				return false if @known_files[file_name] > file_atime
			end

			return true
		end

		def get_changes
			changes = {}

			tNow = Time.now

			@file_mutex.synchronize do
				total_file_list = @known_files.keys + @commited_files.keys
				total_file_list.each do |file|
					next if (@known_files[file] || tNow) <= (@commited_files[file] || Time.at(0))
					changes[file] = @known_files[file] || tNow
				end
			end

			changes
		end

		def commit_changes(changes)
			@file_mutex.synchronize do
				changes.keys.each do |file|
					if(@known_files.include? file)
						@commited_files[file] = [@commited_files[file] || Time.at(0), changes[file]].max
					else
						@commited_files.delete file
					end
				end
			end
		end
	end
end