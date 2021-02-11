
require 'mqtt/sub_handler'
require_relative 'lib/dragon-sync/synced-folder.rb'

$mqtt = MQTT::SubHandler.new('localhost')

opts = {
    mqtt: $mqtt,
#    remote: 'root@xaseiresh.hopto.org',
    remote_dir: '/tmp/test2/', 
};

folder1 = DragonSync::SyncFolder.new(opts.merge({local_dir: '/tmp/test1/'}));

#folder2 = DragonSync::SyncFolder.new(opts.merge({local_dir: '/tmp/test2/'}));

Thread.stop();