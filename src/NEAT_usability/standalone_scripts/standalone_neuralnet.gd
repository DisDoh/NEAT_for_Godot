extends Reference

"""This class builds a neural network that can be used independently without running
the GeneticAlgorithm or Genome nodes, provided it has access to a network
configuration saved under user://network_configs/.
The user has to emulate the behavior of the agent class by simply feeding the update()
method with the array returned by the sense() method on the body, and using the return
value of update() to control the agent with an act() method.
"""

# if set to true, input neurons pass their inputs through the defined activation
# function. If this parameter is not subject to change, CONSIDER REMOVING THE
# CONDITIONAL IN THE UPDATE() FUNCTION.
var activate_inputs = false
# Enumeration for neuron types
enum NEURON_TYPE{input, bias, hidden, output}

# ---- all of these parameters are set once a network config is loaded ----
# Should the network ensure that all inputs have been fully flushed through
# the network (=snapshot), or should it give an output after every neuron has
# been activated once (= active)
var is_runtype_active: bool
# selected activation func
var curr_activation_func: String
# the number of hidden layers in the network.
var depth: int = 1
# flush count is 1 if run_type active, else it is the number of hidden layers.
var flush_count: int
# variables for the neurons in this network.
var all_neurons: Dictionary
var inputs = []
var hiddens = []
var outputs = []
# the output that will be returned by the network.
var output = []
# the currently used activation func, determined by the Params class.
var activation_func: FuncRef

var neurons: Dictionary
var links: Dictionary


class StandaloneNeuron:
	"""A tiny class that is internal to this file to emulate the Neuron Class.
	"""
	var input_connections: Array
	var output: float
	var neuron_id: int
	var activation_curve: float
	var position: Vector2
	var neuron_type: int
	var loop_back: bool
	# these vars are only used once the network starts updating
	var activation_sum: float
	
	func _init(n_id: int, curve: float) -> void:
		neuron_id = n_id
		activation_curve = curve

	func connect_input(in_neuron: StandaloneNeuron, weight: float) -> bool:
		"""Stores a new input connection to the neuron.
		"""
		var linkIsEnabled = true
		var have_neuron = false
		for input in input_connections:
			if input[0].neuron_id == in_neuron.neuron_id:
				have_neuron = true
				linkIsEnabled = false
				break
				
		if not have_neuron:
			input_connections.append([in_neuron, weight])
		return linkIsEnabled
	
	
	
		


func save_to_json(name: String) -> void:
	"""Saves the network configuration in json format under user://network_configs/
	"""
	var network_data = {}
	network_data["network_name"] = name
	# save information about the used activation func and network depth
	network_data["activation_func"] = Params.curr_activation_func
	network_data["runtype_active"] = Params.is_runtype_active
	network_data["depth"] = depth
	# Save all neurons in sorted order
	var sorted_neurons = all_neurons.values()
#	sorted_neurons.sort_custom(self, "sort_neurons_by_pos")
	var neuron_data = []
	for neuron in sorted_neurons:
		var neuron_save = {
			"id" : neuron.neuron_id,
			"curve" : neuron.activation_curve,
			"type" : neuron.neuron_type,
			"posx" : neuron.position.x,
			"posy" : neuron.position.y,
			"loop_back" : neuron.loop_back
#			"activation_sum" : neuron.activation_sum,
#			"activation_curve" : neuron.activation_curve
		}
		neuron_data.append(neuron_save)
	network_data["neurons"] = neuron_data
	# Next save every link in a dictionary format.
	var link_data = []
	for link in links:
		var link_save = {
			"from" : links[link].from,
			"to" : links[link].to,
			"weight" : links[link].weight,
			"enabled" : links[link].enabled
		}
		link_data.append(link_save)
	network_data["links"] = link_data
	# now save the dictionary as a json file in the user path
	var file = File.new()
	var dir = Directory.new()
	# make a new directory for network configs if necessary
	if dir.open("user://network_configs") == ERR_INVALID_PARAMETER:
		dir.make_dir("user://network_configs")
	# save the network in the network directory
	file.open("user://network_configs/%s.json" % name, File.WRITE)
	file.store_string(JSON.print(network_data, "  "))
	file.close()


		
func load_config(network_name: String) -> void:
	"""Opens a config saved under user://network_configs/ and updates the properties
	of this script accordingly.
	"""
	# open the file specified by the network name, store it in a dict
	var file = File.new()
	# If it exists, open file and parse it's contents into a dict, else push error
	if file.open("user://network_configs/%s.json" % network_name, File.READ) != OK:
		push_error("file not found"); breakpoint
	var network_data = parse_json(file.get_as_text())
	file.close()
	#load params config
	Params.load_config("car_params")
	# generate Neurons and put them into appropriate arrays
	for neuron_data in network_data["neurons"]:
		var neuron = StandaloneNeuron.new(int(neuron_data["id"]), neuron_data["curve"])
		all_neurons[neuron_data["id"]] = neuron
		neuron.position.x = neuron_data["posx"]
		neuron.position.y = neuron_data["posy"]
		neuron.neuron_type = neuron_data["type"]
		neuron.loop_back = neuron_data["loop_back"]
#		neuron.activation_sum = neuron_data["activation_sum"]
		match int(neuron_data["type"]):
			NEURON_TYPE.input:
				inputs.append(neuron)
			NEURON_TYPE.bias:
				# bias always outputs 1.0
				neuron.output = 1.0
			NEURON_TYPE.hidden:
				hiddens.append(neuron)
			NEURON_TYPE.output:
				outputs.append(neuron)
	# connect links just like in regular NeuralNet class.
	for link_data in network_data["links"]:
		if link_data.enabled:
			var from_neuron = all_neurons[link_data["from"]]
			var to_neuron = all_neurons[link_data["to"]]
			link_data.enabled = to_neuron.connect_input(from_neuron, float(link_data["weight"]))
	# sort neurons such that they are evaluated left to right, feed_back
	# and loop_back connections are however still delayed (that is desired)
#	hiddens.sort_custom(self, "sort_neurons_by_pos")
	
	neurons = all_neurons
	for i in range(network_data["links"].size()):
		links[str(i)] = network_data["links"][i]
		links[str(i)].to_neuron_id = network_data["links"][i].to
		links[str(i)].from_neuron_id = network_data["links"][i].from
	# extract the rest of the network Metadata
	depth = calculate_depth(hiddens)#network_data["depth"]
	is_runtype_active = network_data["runtype_active"]
	curr_activation_func = network_data["activation_func"]
	# set the flush-count and make a funcref for the chosen activation func
	flush_count = 1 if is_runtype_active else depth
	activation_func = funcref(self, curr_activation_func)

static func calculate_depth(sorted_hiddens: Array) -> int:
	"""Calculate the number of hidden layers by counting the number of neurons with
	unique x positions.
	"""
	var network_depth = 1
	if sorted_hiddens.size() > 0:
		network_depth += 1
	for i in sorted_hiddens.size():
		if sorted_hiddens[i].position.x > sorted_hiddens[i-1].position.x:
			network_depth += 1
	return network_depth

static func get_saved_networks() -> Array:
	"""Returns an array containing the names of every currently saved network
	"""
	var dir = Directory.new()
	# make a new directory for network configs if necessary
	if dir.open("user://network_configs") == ERR_INVALID_PARAMETER:
		push_error("no networks saved yet")
		breakpoint
		return []
	# only show files
	dir.list_dir_begin(true)
	var currDir = dir.get_current_dir()
	# append every file to saved networks array
	var saved_networks = []
	var file_name = "This is just a placeholder"
	while file_name != "":
		file_name = dir.get_next()
		file_name = file_name.rsplit(".", true, 1)[0]
		if file_name != "":
			saved_networks.append(file_name)
	return saved_networks


func update(input_values: Array) -> Array:
	"""Pass the input_values to the input neurons, loop through every neuron once
	and sum up it's input neurons multiplied by their weight.
	If the runtype of the network is snapshot (used for classification tasks) there
	will be enough passes over the neurons in the network until the input values
	have been passed to every neuron and they can be read from the output.
	Finally return the values of output neurons.
	"""
	# happens if the ga node is initialized with the wrong amount of inputs and outputs
	if not (input_values.size() == inputs.size()):
		push_error("Num of inputs not matching num of input neurons"); breakpoint
	# feed the input neurons.
	for i in inputs.size():
		if Params.activate_inputs:
			inputs[i].output = activation_func.call_func(input_values[i])
		else:
			inputs[i].output = input_values[i]
	# step through every hidden neuron (incl. outputs), sum up their weighted
	# input connections, pass them to activate(), and update their output
	for _flush in flush_count:
		for neuron in hiddens + outputs:
			var weighted_sum:float = 0
			for connection in neuron.input_connections:
				var input_neuron = connection[0]; var weight = connection[1]
				weighted_sum += input_neuron.output * weight
			neuron.output = activation_func.call_func(weighted_sum, neuron.activation_curve)
	# copy output of output neurons into output array
	output.clear()
	for out_neuron in outputs:
		output.append(out_neuron.output)
	return output


# --------------- Activation Functions ---------------

static func tanh_activate(weighted_sum: float, activation_modifier: float) -> float:
	"""Standard tanh activation_modifier would be 2. Outputs range -1 to 1.
	"""
	return (2 / (1 + exp(-weighted_sum * activation_modifier))) - 1


static func sigm_activate(weighted_sum: float, activation_modifier: float) -> float:
	"""Standard sigmoid activation_modifier would be 1. Outputs range 0 to 1.
	"""
	return (1 / (1 + exp(-weighted_sum * activation_modifier)))


static func gauss_activate(weighted_sum: float, activation_modifier: float) -> float:
	"""Gaussian function. Outputs range 0 to 1.
	"""
	return exp(-(pow(weighted_sum, 2) / (2 * pow(activation_modifier, 2))))
