
require 'mqtt/sub_handler'
require_relative 'lib/dragon-sync/synced-folder.rb'

$mqtt = MQTT::SubHandler.new('localhost')

opts = {
    mqtt: $mqtt,
    remote: 'root@xaseiresh.hopto.org',
    remote_dir: '/var/exported/temp/dragon-sync', 
};

folder1 = DragonSync::SyncFolder.new(opts.merge({local_dir: '/home/xasin/Xasin/dragon-sync/'}));
#folder2 = DragonSync::SyncFolder.new(opts.merge({local_dir: '/tmp/test2/'}));

Thread.stop();