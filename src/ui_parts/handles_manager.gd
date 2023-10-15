extends TextureRect

var zoom := 1.0:
	set(new_value):
		zoom = new_value
		queue_update_texture()
		queue_redraw()

var texture_update_pending := false
var handles_update_pending := false

var handles: Array[Handle]

func _ready() -> void:
	SVG.root_tag.attribute_changed.connect(queue_full_update)
	SVG.root_tag.child_tag_attribute_changed.connect(queue_update_texture)
	SVG.root_tag.child_tag_attribute_changed.connect(sync_handles)
	SVG.root_tag.tag_added.connect(queue_full_update)
	SVG.root_tag.tag_deleted.connect(queue_full_update.unbind(1))
	SVG.root_tag.changed_unknown.connect(queue_full_update)
	Selections.selection_changed.connect(change_selection)
	queue_full_update()


func queue_full_update() -> void:
	queue_update_texture()
	queue_update_handles()

func queue_update_texture() -> void:
	texture_update_pending = true

func queue_update_handles() -> void:
	handles_update_pending = true

func _process(_delta: float) -> void:
	if texture_update_pending:
		update_texture()
		texture_update_pending = false
	if handles_update_pending:
		update_handles()
		handles_update_pending = false


func update_texture() -> void:
	# Draw a SVG out of the shapes.
	var w: float = SVG.root_tag.attributes.width.value
	var h: float = SVG.root_tag.attributes.height.value
	var viewbox: Rect2 = SVG.root_tag.attributes.viewBox.value
	var svg := '<svg width="%f" height="%f" viewBox="%s"' % [w, h,
			AttributeRect.rect_to_string(viewbox)]
	svg += ' xmlns="http://www.w3.org/2000/svg">'
	for tag in SVG.root_tag.child_tags:
		var attribs := tag.attributes
		match tag.title:
			"circle": svg += '<circle cx="%f" cy="%f" r="%f"' % [attribs.cx.value,
					attribs.cy.value, attribs.r.value]
			"ellipse": svg += '<ellipse cx="%f" cy="%f" rx="%f" ry="%f"' % [attribs.cx.value,
					attribs.cy.value, attribs.rx.value, attribs.ry.value]
			"rect": svg += '<rect x="%f" y="%f" width="%f" height="%f" rx="%f" ry="%f"' %\
					[attribs.x.value, attribs.y.value, attribs.width.value,
					attribs.height.value, attribs.rx.value, attribs.ry.value]
			"path": svg += '<path d="%s"' % [attribs.d.value]
			"line": svg += '<line x1="%f" y1="%f" x2="%f" y2="%f"' % [attribs.x1.value,
					attribs.y1.value, attribs.x2.value, attribs.y2.value]
		svg += ' fill="none" stroke="#000" stroke-width="%f"/>' % [2.0 / zoom]
	svg += "</svg>"
	# Store the SVG string.
	var img := Image.new()
	img.load_svg_from_string(svg, 4.0 * zoom)
	# Update the display.
	var image_texture := ImageTexture.create_from_image(img)
	texture = image_texture

func update_handles() -> void:
	handles.clear()
	for tag in SVG.root_tag.child_tags:
		if tag is TagCircle:
			handles.append(XYHandle.new(tag.attributes.cx, tag.attributes.cy))
		if tag is TagEllipse:
			handles.append(XYHandle.new(tag.attributes.cx, tag.attributes.cy))
		if tag is TagRect:
			handles.append(XYHandle.new(tag.attributes.x, tag.attributes.y))
		if tag is TagLine:
			handles.append(XYHandle.new(tag.attributes.x1, tag.attributes.y1))
			handles.append(XYHandle.new(tag.attributes.x2, tag.attributes.y2))
		if tag is TagPath:
			var path_attribute: AttributePath = tag.attributes.d
			for idx in path_attribute.get_command_count():
				if not path_attribute.get_command(idx) is PathCommand.CloseCommand:
					handles.append(PathHandle.new(path_attribute, idx))

func change_selection() -> void:
	return  # TODO

func sync_handles() -> void:
	# For XYHandles, sync them. For path handles, sync all but the one being dragged.
	for handle_idx in range(handles.size() - 1, -1, -1):
		var handle := handles[handle_idx]
		if handle is XYHandle:
			handle.sync()
		elif handle is PathHandle and not handle.dragged:
			handles.remove_at(handle_idx)
	for tag in SVG.root_tag.child_tags:
		if tag is TagPath:
			var path_attribute: AttributePath = tag.attributes.d
			for idx in path_attribute.get_command_count():
				if not path_attribute.get_command(idx) is PathCommand.CloseCommand:
					var handle := PathHandle.new(path_attribute, idx)
					handles.append(handle)
	queue_redraw()

func _draw() -> void:
	for handle in handles:
		if handle.dragged:
			draw_circle(coords_to_canvas(handle.pos), 4 / zoom, Color(0.3, 0.4, 1.0))
			draw_circle(coords_to_canvas(handle.pos), 2.25 / zoom, Color.WHITE)
		elif handle.hovered:
			draw_circle(coords_to_canvas(handle.pos), 4 / zoom, Color(0.7, 0.7, 0.7))
			draw_circle(coords_to_canvas(handle.pos), 2.25 / zoom, Color.WHITE)
		else:
			draw_circle(coords_to_canvas(handle.pos), 4 / zoom, Color.BLACK)
			draw_circle(coords_to_canvas(handle.pos), 2.25 / zoom, Color.WHITE)

func coords_to_canvas(pos: Vector2) -> Vector2:
	return size / Vector2(SVG.root_tag.attributes.width.value,
			SVG.root_tag.attributes.height.value) * pos

func canvas_to_coords(pos: Vector2) -> Vector2:
	return pos * Vector2(SVG.root_tag.attributes.width.value,
			SVG.root_tag.attributes.height.value) / size


func _unhandled_input(event: InputEvent) -> void:
	var max_grab_distance := 9 / zoom
	if event is InputEventMouseMotion:
		var event_pos = event.position - global_position
		for handle in handles:
			if handle.dragged:
				handle.set_pos(canvas_to_coords(event_pos))
				accept_event()
		var picked_hover := false
		for handle in handles:
			if not picked_hover and event_pos.distance_to(
			coords_to_canvas(handle.pos)) < max_grab_distance:
				handle.hovered = true
				picked_hover = true
				queue_redraw()
				break
			if picked_hover and handle.hovered:
				handle.hovered = false
			if handle.hovered != (event_pos.distance_to(
			coords_to_canvas(handle.pos)) < max_grab_distance):
				handle.hovered = not handle.hovered
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			for handle in handles:
				if handle.hovered:
					handle.dragged = true
					queue_redraw()
		else:
			for handle in handles:
				if handle.dragged:
					handle.dragged = false
					queue_redraw()