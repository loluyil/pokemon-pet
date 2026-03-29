extends Node3D

@onready var sub_viewport = $SubViewport
@onready var mesh_instance_3d = $SubViewport/Node3D/MeshInstance3D

@export var mesh_to_snapshot: ArrayMesh
@export var snapshot_name: String

func _ready():
	mesh_instance_3d.mesh = mesh_to_snapshot
	
	# Force one render frame
	await RenderingServer.frame_post_draw
	
	# Get image from the SubViewport texture
	var img = sub_viewport.get_texture().get_image()
	
	# IMPORTANT: Flip it vertically (SubViewport renders upside down)
	img.flip_y()
	
	var image_path = "res://models/meshes/%s.png" % snapshot_name
	img.save_png(image_path)
