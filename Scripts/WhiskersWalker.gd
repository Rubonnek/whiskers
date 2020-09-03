class_name WhiskersWalker
extends Resource

var m_dialogue_data : Dictionary
var m_current_block : Dictionary
var m_format_dictionary : Dictionary = {} setget set_format_dictionary
# TODO: Remove redundant(?) default_base_instance
# TODO: Change base instance to WeakRef to avoid cyclic dependencies
var m_base_instance : Object = null# Object used as a base instance when running expressions

func set_dialogue_data(p_dialogue_data : Dictionary) -> void:
	m_dialogue_data = p_dialogue_data

func _init(p_base_instance : Object = null) -> void:
	m_base_instance = p_base_instance
	
func open_whiskers(p_json_path : String) -> void:
	var file = File.new()
	
	var error = file.open(p_json_path, File.READ)
	if error:
		push_error("couldn't open file at %s. Error number %s." % [p_json_path, error])
	
	m_dialogue_data = parse_json(file.get_as_text())
	file.close()

func start_dialogue() -> Dictionary:
	if not m_dialogue_data.has("Start"):
		push_error("not a valid whiskers dictionary, it does not have a 'Start' key.")
		return {}
	
	m_current_block = generate_block(m_dialogue_data.Start.connects_to.front())
	
	return m_current_block

func end_dialogue() -> void:
	m_dialogue_data = {}
	m_current_block = {}
	m_base_instance = null

func next(selected_option_key : String = "") -> Dictionary:
	if not m_dialogue_data:
		push_warning("trying to call next() on a finalized dialogue.")
		return {}

	if m_current_block.is_final:
		# It is a final block, but it could be connected to more than an END node, we have to process them
		var _null_block = process_block(m_current_block)
		end_dialogue()
		return {}
	
	var next_block = {}
	
	var _results = handle_expressions(m_current_block.expressions)
	
	# DEALING WITH OPTIONS
	if selected_option_key:
		# Generate a block containing all the nodes that this options is connected with
		var option_block = generate_block(selected_option_key)
		if option_block.empty():
			push_warning("Option block empty. Was this intended?")
			return {}
		
		next_block = process_block(option_block)
		
	elif not m_current_block.options.empty():
		push_warning("no option was passed as argument, but there was options available. This could cause an infinite loop. Use wisely.")
	
	else:
		next_block = process_block(m_current_block)
	
	m_current_block = next_block
	
	return m_current_block

func process_block(block : Dictionary) -> Dictionary:
	var next_block = {}
	
	var _results = handle_expressions(block.expressions)
	
	if not block.dialogue.empty():
		next_block = generate_block(block.dialogue.key)
	elif not block.jump.empty():
		next_block = handle_jump(block.jump)
	elif not block.condition.empty():
		next_block = handle_condition(block.condition)
	
	return next_block

func handle_expressions(expressions_array : Array) -> Array:
	if expressions_array.empty(): return []
	
	var results = []
	
	for dic in expressions_array:
		results.append(execute_expression(dic.logic))
	
	return results

func handle_condition(condition : Dictionary) -> Dictionary:
	var result = execute_expression(condition.logic)
	var next_block = {}
	
	if not result is bool:
		push_error("the expression used as input for a condition node should return a boolean, but it is returning %s instead." % result)
		return {}
	
	if result:
		if not "End" in condition.goes_to_key.if_true: # If a condition node goest to an end node, then we have to end the dialogue
			next_block = generate_block(condition.goes_to_key.if_true)
	else:
		if not "End" in condition.goes_to_key.if_false:
			next_block = generate_block(condition.goes_to_key.if_false)
	
	return next_block

func handle_jump(jump) -> Dictionary:
	# Get the matching node to wich we are going
	var jumped_to = generate_block(jump.goes_to_key)
	var next_block = {}
	
	# If this node has expressions that it is connected to, than we want to execute them
	var _resutls = handle_expressions(jumped_to.expressions)
	
	if not jumped_to.dialogue.empty():
		next_block = generate_block(jumped_to.dialogue.key)
	elif not jumped_to.jump.empty():
		next_block = handle_jump(jumped_to.jump)
	elif not jumped_to.condition.empty():
		next_block = handle_condition(jumped_to.condition)
	elif not jumped_to.options.empty():
		next_block = jumped_to
	
	return next_block

func execute_expression(expression_text : String):
	var expression = Expression.new()
	var result = null

	var error = expression.parse(expression_text)
	if error:
		push_error("unable to parse expression %s. Error: %s." % [expression_text, error])
	else:
		result = expression.execute([], m_base_instance, true)
		if expression.has_execute_failed():
			push_error("unable to execute expression %s." % expression_text)
	
	return result

# A block is a Dictionary containing a node and every node it is connected to, by type and it's informations.
func generate_block(node_key : String) -> Dictionary:
	if not m_dialogue_data.has(node_key):
		push_error("trying to create block from inexisting node %s. Aborting." % node_key)
		return {}
		
	# Block template
	var block = {
			key = node_key,
			options = [], # key, text
			expressions = [], # key, logic
			dialogue = {}, # key, text
			condition = {}, # key, logic, goes_to_key["true"], goes_to_key["false"]
			jump = {}, # key, id, goes_to_key
			is_final = false
			}
	
	if "Dialogue" in node_key:
		block.text = m_dialogue_data[node_key].text.format(m_format_dictionary)
	
	if "Jump" in node_key:
		for key in m_dialogue_data:
			if "Jump" in key and m_dialogue_data[node_key].text == m_dialogue_data[key].text and node_key != key:
				block = generate_block(m_dialogue_data[key].connects_to[0])
				break
	
	if "Condition" in node_key: # this isn't very DRY
		block.condition = process_condition(node_key)
		block = process_block(block)

	# For each key of the connected nodes we put it on the block
	for connected_node_key in m_dialogue_data[node_key].connects_to:
		if "Dialogue" in connected_node_key:
			if not block.dialogue.empty(): # It doesn't make sense to connect two dialogue nodes
				push_warning("more than one Dialogue node connected. Defaulting to the first, key: %s, text: %s." % [block.dialogue.key, block.text])
				continue
			
			var dialogue = {
					key = connected_node_key,
					}
			block.dialogue = dialogue
			
		elif "Option" in connected_node_key:
			var option = {
					key = connected_node_key,
					text = m_dialogue_data[connected_node_key].text,
					}
			block.options.append(option)
			
		elif "Expression" in connected_node_key:
			var expression = {
					key = connected_node_key,
					logic = m_dialogue_data[connected_node_key].logic
					}
			block.expressions.append(expression)
			
		elif "Condition" in connected_node_key:
			if not block.condition.empty(): # It also doesn't make sense to connect two Condition nodes
				push_warning("more than one Condition node connected. Defaulting to the first, key: %s." % block.condition.key)
				continue
			
			block.condition = process_condition(connected_node_key)
			
			var parse_condition = handle_condition(block.condition)
			
			if 'Option' in parse_condition.key:
				var option = {
						key = parse_condition.key,
						text = m_dialogue_data[parse_condition.key].text,
					}
				block.options.append(option)
		
		elif "Jump" in connected_node_key:
			if not block.jump.empty():
				push_warning("more than one Jump node connected. Defaulting to the first, key: %s, id: %d." % [connected_node_key, block.jump.id])
				continue
			
			# Just like with the Expression node a linear search is needed to find the matching jump node.
			var match_key : String
			for key in m_dialogue_data:
				if "Jump" in key and m_dialogue_data[connected_node_key].text == m_dialogue_data[key].text and connected_node_key != key:
					match_key = key
					break
			
			if not match_key:
				push_error("no other node with the id %s was found. Aborting." % m_dialogue_data[connected_node_key].text)
				return {}
				
			var jump = {
					key = connected_node_key,
					id = m_dialogue_data[connected_node_key].text,
					goes_to_key = match_key
					}
			block.jump = jump
			
			var jump_options = handle_jump(block.jump)
			if not jump_options.options.empty():
				for option in jump_options.options:
					block.options.append(option)
			
		elif "End" in connected_node_key and not "Jump" in node_key:
			block.is_final = true
	
	m_current_block = block
	return m_current_block

func process_condition(passed_key : String) -> Dictionary:
	# Sadly the only way to find the Expression node that serves as input is to make a linear search
	var input_logic : String
	for key in m_dialogue_data:
		if "Expression" in key and m_dialogue_data[key].connects_to.front() == passed_key:
			input_logic = m_dialogue_data[key].logic
			break
	
	if not input_logic:
		push_error("no input for the condition node %s was found." % passed_key)
		return {}
	
	var condition = {
			key = passed_key,
			logic = input_logic,
			goes_to_key = {
					if_true = m_dialogue_data[passed_key].conditions["true"],
					if_false = m_dialogue_data[passed_key].conditions["false"]
					}
			}
	
	return condition

func set_format_dictionary(value : Dictionary) -> void:
	m_format_dictionary = value
