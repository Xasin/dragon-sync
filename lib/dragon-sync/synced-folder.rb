
require_relative 'folder-watcher.rb'

module DragonSync
    class SyncFolder
        def initialize(settings)
            @settings = settings;

            @remote_host = settings[:remote];
        
            @local_dir = settings[:local_dir]
            @remote_dir = settings[:remote_dir]

            @mqtt = settings[:mqtt];
            raise ArgumentError, "MQTT connection must be specified!" unless @mqtt.is_a? MQTT::SubHandler
            @mqtt_topic = "#{settings[:mqtt_root] || 'DragonSync'}#{@remote_dir}".chomp('/');
            
            @folder_watcher = FolderWatcher.new(@local_dir)

            @autopush_delay = settings[:autopush_delay] || 10;
            @remote_atime = Time.at(0)
            @remote_last_pulled_atime = Time.at(0)

            @update_thread = nil;

            @mqtt.subscribe_to @mqtt_topic do |data|
                @remote_atime = Time.at(data.to_f);

                @update_thread&.run() if (@remote_atime - @remote_last_pulled_atime)
            end

            @folder_watcher.rescan_files
            @folder_watcher.on_file_change() { @update_thread&.run }

            start_update_thread

            @folder_watcher.start_inotify
        end

        def start_update_thread()
            return unless @update_thread.nil?

            @update_thread = Thread.new do
                loop do
                    if @remote_atime > @remote_last_pulled_atime
                    elsif !@folder_watcher.up_to_date?
                        sleep [1, @autopush_delay - (Time.now() - @folder_watcher.latest_atime)].max
                    else
                        Thread.stop 
                    end

                    # If we have changes that need to be pushed, do so here:
                    if((!@folder_watcher.up_to_date?()) && 
                         ((Time.now - @folder_watcher.latest_atime > @autopush_delay) || 
                         (@remote_atime > @remote_last_pulled_atime)))

                        push_folder
                    end

                    next unless @folder_watcher.up_to_date?

                    pull_folder if @remote_atime > @remote_last_pulled_atime
                end
            end

            @update_thread.abort_on_exception = true;
        end

        private def generate_file_includes(file_list)
            file_includes = {};

            file_list.each do |fName|
                file_includes[fName] = true;

                dir_list = fName.split('/')[0..-2];
                dir_str = '';
                dir_list.each do |dir|
                    dir_str += dir + '/';
                    file_includes[dir_str] = true;
                end
            end

            file_includes.keys.map { |fname| "--include=#{fname}"} + ['--exclude=*']
        end

        private def call_rsync(from, to, **extra_opts)
            rsync_command_opts = {
                '-q' => true,
                '-r' => true,
                '-l' => true,
                '-u' => true,
                '-t' => true,
                '-E' => true,
                '--delete' => true,
                '-m' => true
            };

            file_include_list= [];
            if(extra_opts.include? :files)
                file_include_list = generate_file_includes extra_opts[:files]
                extra_opts.delete :files
            end

            rsync_command_opts.merge!(@settings[:rsync_opts] || {});

            rsync_command_opts.merge!(extra_opts);
            rsync_command_opts.keep_if() { |k,v| (v == true) || (v.is_a?(String)) }

            rsync_command_list = ['rsync', rsync_command_opts.keys, file_include_list, from, to].flatten

            puts "Rsync command: #{rsync_command_list.join(' ')}"

            system(*rsync_command_list)
        end

        def push_folder()
            puts "Pushing changes from #{@local_dir}"

            changes = @folder_watcher.get_changes

            remote_str = @remote_host.nil? ? @remote_dir : "#{@remote_host}:#{@remote_dir}";
            return false unless call_rsync(@local_dir, remote_str, files: changes.keys);

            @folder_watcher.commit_changes changes

            @remote_last_pulled_atime = @folder_watcher.latest_atime
            @remote_atime = @folder_watcher.latest_atime

            @mqtt.publish_to @mqtt_topic, @remote_atime.to_f, retain: true

            true
        end

        def pull_folder()
            puts "Pulling to #{@local_dir}"

            remote_str = @remote_host.nil? ? @remote_dir : "#{@remote_host}:#{@remote_dir}";
            return false unless call_rsync(remote_str, @local_dir);

            @remote_last_pulled_atime = @remote_atime

            true;
        end
    end
end