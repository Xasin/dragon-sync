
require 'mqtt/sub_handler'
require_relative 'lib/dragon-sync/synced-folder.rb'

$mqtt = MQTT::SubHandler.new('xaseiresh.hopto.org')

opts = {
    mqtt: $mqtt,
    remote: 'root@xaseiresh.hopto.org',
    remote_dir: '/tmp/test/', 
};

folder1 = DragonSync::SyncFolder.new(opts.merge({local_dir: File.expand_path('test_dir/folder1') + '/'}));
folder2 = DragonSync::SyncFolder.new(opts.merge({local_dir: File.expand_path('test_dir/folder2') + '/'}));

Thread.stop();