
Gem::Specification.new do |s|
	s.name        = 'dragon-sync'
	s.version     = '0.1.0'
	s.date        = '2021-02-07'
	s.summary     = "rsync based folder synchronization and archiving"
	s.description = "This gem will synchronize specified folders using rsync to a server, and will use MQTT to notify other systems of updates."
	s.authors     = ["Xasin", "Neira", "Mesh"]
	s.files       = [	"lib/mqtt/base_handler.rb",
							"README.md"]
	s.homepage    = 'https://github.com/Xasin/dragon-sync'
	s.license     = 'GPL-3.0'

	s.add_runtime_dependency "mqtt-sub_handler", ">= 0.1.6"
	s.add_runtime_dependency "xasin-logger", "~> 0.1"
end
