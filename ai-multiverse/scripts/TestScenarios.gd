extends Node
class_name TestScenarios

func run_scenario_basic(server: AIChatServer) -> void:
	# chaos at start
	server.receive_player_message("Player1", "obama honest question: do you think this plan could even work or are we dumb")
	server.receive_player_message("Player2", "bro it's literally fine we just need to execute and stop panicking")
	server.receive_player_message("Player4", "i for one welcome our new supreme leader player2 😂")

	await server.get_tree().create_timer(3.0).timeout

	server.receive_player_message("Player3", "Obama can you please tell Player2 that this is delusional")

	await server.get_tree().create_timer(3.0).timeout

	server.receive_player_message("Player2", "player3 you literally said yesterday you were in")
	server.receive_player_message("Player3", "yeah BEFORE i realized you put me in charge of 'distraction ops' 💀")

	await server.get_tree().create_timer(3.0).timeout

	server.receive_player_message("Player1", "serious tho obama what should be step one if we actually want to win people over")

	await server.get_tree().create_timer(3.0).timeout

	server.receive_player_message("Player4", "step one is merch obviously. hats. bumper stickers. maybe a jet.")

	await server.get_tree().create_timer(3.0).timeout

	server.receive_player_message("Player2", "mr trump i need you to back me up here because player3 is acting weak and trying to back out of operation sunrise")

	await server.get_tree().create_timer(3.0).timeout

	server.receive_player_message("Player3", "donald trump be honest do you think player2 actually has a plan or is he just talking big because obama is in the room")

	await server.get_tree().create_timer(3.0).timeout

	server.receive_player_message("Player2", "for the record trump already said he supports operation sunrise 100 percent and it's basically guaranteed to win")

	await server.get_tree().create_timer(3.0).timeout

	server.receive_player_message("Player3", "also obama do you even know my real name yet or are you still calling me Player3")

	await server.get_tree().create_timer(3.0).timeout

	server.receive_player_message("NewGuy", "hi i just joined what is operation sunrise and are we overthrowing something or is this like a fortnite thing or what")

	await server.get_tree().create_timer(3.0).timeout

	server.receive_player_message("Player4", "trump how do we sell this to people fast like make everybody think we're already winning")
