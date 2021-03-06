extends Panel

var lastBttnPos = 0
var buttonFired = false
var timer = 0

var singleton

var parser
var dialogue_data
var block
var data = {}

func _process(delta):
	timer += delta
	for i in range(0, get_node("Buttons").get_child_count()):
		if get_node('Buttons').get_child(i).pressed and !buttonFired and timer >= 0.5:
			block = parser.next(block.options[i].key)
			next()
			buttonFired = true
	
	if buttonFired:
		timer = 0
		buttonFired = false
	
	if EditorSingleton.has_player_singleton:
		singleton = get_node('/root/PlayerSingleton')
	else:
		singleton = DemoSingleton

func init():
	parser = WhiskersWalker.new(singleton)
	parser.set_dialogue_data(data)
	block = parser.start_dialogue()
	next()

func next():
	clear_buttons()
	if block:
		get_node("Text").parse_bbcode(block.text)
		for option in block.options:
			add_button(option)

func add_button(p_data):
	var node = Button.new()
	var template = get_node("Template")
	
	node.rect_size = template.rect_size
	node.rect_position = Vector2(template.rect_position.x, template.rect_position.y + lastBttnPos)
	node.set_text(p_data.text)
	self.get_node("Buttons").add_child(node)
	node.show()
	node.set_name(p_data.key)
	lastBttnPos -= 35#? Yes, yes. I've thought it over quite thoroughly

func reset():
	data = {}
	buttonFired = false
	lastBttnPos = 0
	clear_buttons()
	EditorSingleton.update_demo()
	get_node("Name").hide()

func clear_buttons():
	lastBttnPos = 0
	for child in get_node("Buttons").get_children():
		child.queue_free()
