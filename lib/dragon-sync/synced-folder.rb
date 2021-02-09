
require 'rb-inotify'

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

            @local_atime  = Time.at(0);
            @remote_atime = Time.at(0)

            @autopush_delay = settings[:autopush_delay] || 10;

            @inotify_thread = nil;
            @update_thread = nil;

            @mqtt.subscribe_to @mqtt_topic do |data|
                @remote_atime = Time.at(data.to_f);

                @update_thread&.run() if (@remote_atime - @local_atime) > 1
            end

            sleep 1

            determine_local_atime

            start_inotify_thread
            start_update_thread
        end

        def determine_local_atime()
            @local_atime = Time.at(`find #{@local_dir} -printf '%T@ '`.split(' ').map() { |i| i.to_f }.max || 0)
            @update_thread&.run

            nil
        end

        def start_update_thread()
            return unless @update_thread.nil?

            @update_thread = Thread.new do
                loop do
                    pull_folder if (@remote_atime - @local_atime) > 1
                    push_folder if ((@local_atime - @remote_atime) > 1) && ((Time.now() - @local_atime) > @autopush_delay)

                    if(@local_atime - @remote_atime) > 1
                        sleep [1, @autopush_delay - (Time.now() - @local_atime)].max
                    else
                        Thread.stop()   # Always wait for something to happen
                    end
                end
            end

            @update_thread.abort_on_exception = true;
        end

        def start_inotify_thread()
            return unless @inotify_thread.nil?

            @inotify_instance = INotify::Notifier.new
            @inotify_instance.watch(@local_dir, :recursive, :close_write, :move, :create, :delete) do
                @local_atime = Time.now
                @update_thread&.run
            end

            @inotify_thread = Thread.new do
                @inotify_instance.run
            end

            @inotify_thread.abort_on_exception = true
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

            rsync_command_opts.merge!(@settings[:rsync_opts] || {});

            rsync_command_opts.merge!(extra_opts);
            rsync_command_opts.keep_if() { |k,v| (v == true) || (v.is_a?(String)) }

            system(*(['rsync', rsync_command_opts.keys, from, to].flatten))
        end

        def push_folder()
            puts "Pushing changes to #{@local_dir}"

            remote_str = @remote_host.nil? ? @remote_dir : "#{@remote_host}:#{@remote_dir}";
            return false unless call_rsync(@local_dir, remote_str);

            @remote_atime = @local_atime;
            @mqtt.publish_to @mqtt_topic, @local_atime.to_f, retain: true

            true;
        end

        def pull_folder()
            puts "Pulling from #{@local_dir}"

            remote_str = @remote_host.nil? ? @remote_dir : "#{@remote_host}:#{@remote_dir}";
            return false unless call_rsync(remote_str, @local_dir);

            @local_atime = @remote_atime
            true;
        end

        def notify_change()
            @local_atime = Time.now();

            @update_thread&.run() if (@local_atime - @remote_atime) > 1
        end
    end
end