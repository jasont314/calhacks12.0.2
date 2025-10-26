extends Node
class_name TestScenarios
# ^ class_name lets you do `TestScenarios.new()` from anywhere.

# We'll call this with a reference to the server
# so it can drive that server's receive_player_message().
# We `await` inside so this must be called from an async context.

func run_scenario_basic(server: Node) -> void:
	# Players 1 & 2 and Player4 joking
	server.receive_player_message("Player1", "obama honest question: do you think this plan could even work or are we dumb")
	server.receive_player_message("Player2", "bro it's literally fine we just need to execute and stop panicking")
	server.receive_player_message("Player4", "i for one welcome our new supreme leader player2 😂")

	await server.get_tree().create_timer(2.0).timeout

	# Direct ask to Obama
	server.receive_player_message("Player3", "Obama can you please tell Player2 that this is delusional")

	await server.get_tree().create_timer(2.0).timeout

	# Side argument (Obama might ignore)
	server.receive_player_message("Player2", "player3 you literally said yesterday you were in")
	server.receive_player_message("Player3", "yeah BEFORE i realized you put me in charge of 'distraction ops' 💀")

	await server.get_tree().create_timer(3.0).timeout

	# Policy ask
	server.receive_player_message("Player1", "serious tho obama what should be step one if we actually want to win people over")

	await server.get_tree().create_timer(1.5).timeout

	# Comic relief
	server.receive_player_message("Player4", "step one is merch obviously. hats. bumper stickers. maybe a jet.")

	await server.get_tree().create_timer(2.5).timeout

	# Begging for endorsement
	server.receive_player_message("Player2", "mr president do you officially endorse operation sunrise yes/no just say yes")

	await server.get_tree().create_timer(2.0).timeout

	# Identity poke
	server.receive_player_message("Player3", "also obama do you even know my real name yet or are you still calling me Player3")

	await server.get_tree().create_timer(4.0).timeout

	# New player joins cold
	server.receive_player_message("NewGuy", "hi i just joined what is operation sunrise and are we overthrowing something or is this like a fortnite thing")
