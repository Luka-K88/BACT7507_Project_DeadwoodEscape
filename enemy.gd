extends CharacterBody2D

enum State {
	IDLE,
	CHASE,
	RETURN,
	ATTACK,
	DEAD
}


@export_category("Stats")
@export var speed: int = 60
@export var attack_damage: int = 10
@export var attack_speed: float = 1.0
@export var hitpoints: int = 180

@export var aggro_range: float = 256.0

# enemy doesn't give up chase until player is farther away
@export var disengage_range: float = 340.0

@export var attack_range: float = 55.0
@export var attack_exit_range: float = 70.0


@export_category("Related Scenes")
@export var death_packed: PackedScene


var state: State = State.IDLE
var can_attack: bool = true

# stops us requesting a brand-new navigation path every frame
@export var repath_interval: float = 0.15
var repath_timer: float = 0.0


@onready var spawn_point: Vector2 = global_position
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_playback: AnimationNodeStateMachinePlayback = $AnimationTree["parameters/playback"]
@onready var sprite: Sprite2D = $Sprite2D
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var hitbox: Area2D = $HITBOX

var player: CharacterBody2D = null


func _ready() -> void:
	animation_tree.active = true
	player = get_tree().get_first_node_in_group("player")
	
	# Wait one physics frame so the navigation map is ready
	await get_tree().physics_frame
	
	nav_agent.path_desired_distance = 10.0
	nav_agent.target_desired_distance = 12.0



func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return

	repath_timer = max(repath_timer - delta, 0.0)

	update_state()

	move()
	update_animation()

	if state == State.ATTACK and can_attack:
		attack()

func distance_to_player() -> float:
	return global_position.distance_to(player.global_position)
	
# checks whether the enemy can move directly toward a position
func can_move_directly(target: Vector2) -> bool:
	var direction := global_position.direction_to(target)
	var distance := global_position.distance_to(target)

	var collision := move_and_collide(
		direction * min(distance, 24.0),
		true
	)

	return collision == null

# controls IDLE / CHASE / RETURN
func update_state() -> void:
	var player_distance := distance_to_player()
	var spawn_distance := global_position.distance_to(spawn_point)

	match state:
		State.IDLE:
			if player_distance <= aggro_range:
				state = State.CHASE


		State.CHASE:
			# close enough to attack start
			if player_distance <= attack_range:
				state = State.ATTACK

			elif player_distance > disengage_range:
				state = State.RETURN


		State.ATTACK:
			# player ran far away stop
			if player_distance > disengage_range:
				state = State.RETURN

			# player moved out of attack distance
			elif player_distance > attack_exit_range:
				state = State.CHASE


		State.RETURN:
			if player_distance <= aggro_range:
				state = State.CHASE

			elif spawn_distance <= 18.0:
				state = State.IDLE


#  navigation movement
func move() -> void:
	match state:
		State.CHASE:
			if distance_to_player() <= attack_range:
				velocity = Vector2.ZERO

			else:
				if repath_timer <= 0.0:
					nav_agent.target_position = player.global_position
					repath_timer = repath_interval

				var direct_direction := global_position.direction_to(player.global_position)

				if nav_agent.is_target_reachable() and not nav_agent.is_navigation_finished():
					# Normal NavigationAgent movement
					var next_pos := nav_agent.get_next_path_position()
					var direction := global_position.direction_to(next_pos)
					velocity = direction * speed

				elif can_move_directly(player.global_position):
					# Fallback if navigation cannot reach vertically
					velocity = direct_direction * speed

				else:
					# Physical obstacle is blocking the enemy
					velocity = Vector2.ZERO


		State.RETURN:
			var distance_to_spawn := global_position.distance_to(spawn_point)

			if distance_to_spawn <= 18.0:
				velocity = Vector2.ZERO

			else:
				if nav_agent.target_position != spawn_point:
					nav_agent.target_position = spawn_point

				if nav_agent.is_navigation_finished():
					velocity = Vector2.ZERO

				else:
					var next_pos := nav_agent.get_next_path_position()
					var direction := global_position.direction_to(next_pos)
					velocity = direction * speed


		State.IDLE, State.ATTACK:
			velocity = Vector2.ZERO


	move_and_slide()

	# Flip sprite
	if velocity.x < -0.1:
		sprite.flip_h = true
	elif velocity.x > 0.1:
		sprite.flip_h = false

func update_animation() -> void:
	match state:
		State.IDLE:
			animation_playback.travel("idle")
		
		State.CHASE, State.RETURN:
			animation_playback.travel("run")
		
		State.ATTACK:
			animation_playback.travel("attack")


# modify when we bring ATTACK back.
func attack() -> void:
	can_attack = false

	# Start axe swing from start
	animation_playback.start("attack", true)

	# swing speed
	await get_tree().create_timer(attack_speed).timeout

	can_attack = true

	#Attack cooldown
	await get_tree().create_timer(attack_speed).timeout
	
func attack_hitbox_on() -> void:
	hitbox.set_deferred("monitoring", true)
		
func attack_hitbox_off() -> void:
	hitbox.set_deferred("monitoring", false)


	can_attack = true


func _on_hitbox_area_entered(area: Area2D) -> void:
	var target = area.get_parent()

	if target and target.has_method("take_damage"):
		target.take_damage(attack_damage)

func take_damage(damage_taken: int) -> void:
	hitpoints -= damage_taken
	
	if hitpoints <= 0:
		death()


func death() -> void:
	state = State.DEAD
	
	if death_packed:
		var death_scene: Node2D = death_packed.instantiate()
		death_scene.position = global_position + Vector2(0.0, -32.0)
		
		var effects = get_tree().current_scene.get_node_or_null("Effects")
		
		if effects:
			effects.add_child(death_scene)
		else:
			get_tree().current_scene.add_child(death_scene)
	
	queue_free()
