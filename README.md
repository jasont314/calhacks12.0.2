# AI Multiverse - CalHacks 12.0

## Description
AI Multiverse is an interactive game experience that combines GDScript-based game logic with Python-driven AI integrations, allowing players to explore and engage with diverse AI personalities (our favorites being Trump, Obama, and Spongebob). It features real-time voice input and AI-powered character behavior within a game-engine environment, showcasing a fusion of voice control, AI agents, and interactive gameplay.

## Inspiration
We were inspired by games that emphasise social gameplay and interaction, like VRChat and Lethal Company. We were also inspired by popular videos of US presidents playing Minecraft together and CharacterAI, where you can speak with anyone you want! We wanted to create an experience which emphasises those kinds of wacky scenarios, where you and your friends can interact with famous personalities. We also wanted to clip farm.

## What It Does
Sort of a VRChat meets CharacterAI situation— a multiplayer social lounge where you can spawn in supported personalities, ranging from Spongebob Squarepants to Barack Obama, and then you and your friends can speak with them and each other! The AIs can also speak (and get into heated debates) with each other, adding further chaos and fun!

## How We Built It
We used the Godot game engine to create a world and multiplayer experience that multiple machines can log into. It supports voice chat through Mumble. When a user speaks, we created a pipeline that uses Fish Audio to analyse the speech, and the data gets sent to Janitor AI, which has many personalities. We use AI to copy the mannerisms and behaviours of the personalities involved. Just like a real conversation, the AI can choose to respond or not. If so, we use Fish Audio again to convert the response to speech that sounds exactly like Peter Griffin, or whoever you want it to be! The possibilities are endless.

## Challenges We Ran Into
We ran into a lot of issues with multiplayer and Godot, as none of us ever worked with a game engine and multiplayer networks before. There was a big learning curve that we had to get over, and we came up with very interesting solutions to problems. Integration was a big challenge as we were inexperienced with working with team projects from start to deployment, but with the help of AI and other hackers we were able to create efficient systems to bring it all together.

## Accomplishments That We’re Proud Of
Two of our members had never done a hackathon before! We’re really happy we gave it our all. We were also really proud of how we were able to pick up tools and skills like Godot as none of us had ever worked with them. Godot had many limitations, like a bug with the microphone, but we were able to quickly get around it by making our own invisible VOIP server that runs in the background. It was also really tricky to make the AI talk to each other, and that required some ingenious planning to develop a system that encouraged the personality AI to converse in an active discussion.

## What We Learned
We learned many skills like systems engineering and planning, network protocols with multiplayer, working with user APIs, handling timings for different events, Docker, Godot, working with LLMs and Text-to-Speech and Speech-to-Text models. Most importantly, we learnt to work in a team, practising effective communication and planning to finish before the deadline.
