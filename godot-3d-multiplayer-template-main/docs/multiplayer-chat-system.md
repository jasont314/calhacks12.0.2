# Multiplayer Chat System

## Overview

The multiplayer chat system provides **real-time global communication** between all connected players in the game. It features a clean, modular UI design with automatic message formatting, history management, and seamless integration with the multiplayer networking layer.

## Architecture

### Core Components

- **MultiplayerChatUI** (`scenes/ui/multiplayer_chat_ui.tscn`) - Chat UI scene with input and display
- **MultiplayerChatUI** (`scripts/multiplayer_chat_ui.gd`) - Chat logic and message handling
- **Level Integration** (`scripts/level.gd`) - Chat toggle and RPC communication
- **Network Layer** (`scripts/network.gd`) - Player nickname management

### Modular Design

- **Separate Scene**: Chat UI is decoupled from the main level
- **Signal-Based Communication**: Uses signals for loose coupling with the level
- **Reusable Component**: Can be easily added to other scenes or projects

## Client-Server Interactions

### 1. Message Sending

**User Input Flow**
```
User: Types message and presses Enter/Send
Client: Validates message (removes empty messages)
Client -> Server: msg_rpc(nickname, message)
Server: Broadcasts to all clients
All Clients: Receive and display message
```

### 2. Message Broadcasting

**RPC Communication**
```gdscript
# Client sends message
rpc("msg_rpc", nickname, message)

# Server broadcasts to all clients
@rpc("any_peer", "call_local")
func msg_rpc(nick, msg):
    multiplayer_chat.add_message(nick, msg)
```

### 3. Chat Visibility Toggle

**UI State Management**
```
User: Presses Ctrl key (toggle_chat action)
Client: Calls toggle_chat()
UI: Shows/hides chat panel
Focus: Automatically grabs input focus when opening
```

## RPC Methods

### Client → Server RPCs

| Method | Parameters | Description | Validation |
|--------|------------|-------------|------------|
| `msg_rpc()` | `nick, msg` | Send message to all players | Non-empty message, valid nickname |

### Server → Client RPCs

| Method | Parameters | Description | Security |
|--------|------------|-------------|----------|
| `msg_rpc()` | `nick, msg` | Broadcast message to all clients | All clients receive all messages |

## UI Features

### Message Display
- **Timestamp**: Automatic time formatting for each message
- **Nickname**: Player identifier from network system
- **Auto-scroll**: Automatically scrolls to latest message
- **History Limit**: Keeps last 100 messages in memory

### Input Handling
- **Enter Key**: Send message with Enter key
- **Send Button**: Alternative send method
- **Focus Management**: Automatically focuses input when opening
- **Empty Validation**: Prevents sending empty messages

## Usage Examples

### Opening Chat
```gdscript
# Level.gd - Toggle chat visibility
func toggle_chat():
    if main_menu.is_menu_visible():
        return
    multiplayer_chat.toggle_chat()
    chat_visible = multiplayer_chat.is_chat_visible()
```

### Sending Messages
```gdscript
# User types message and presses Enter
func _input(event):
    if event is InputEventKey and event.keycode == KEY_ENTER and event.pressed:
        if chat_visible and multiplayer_chat.message.has_focus():
            multiplayer_chat._on_send_pressed()
            get_viewport().set_input_as_handled()
```

### Message Processing
```gdscript
# Handle message from UI
func _on_chat_message_sent(message_text: String):
    var trimmed_message = message_text.strip_edges()
    if trimmed_message == "":
        return # do not send empty messages

    var nick = Network.players[multiplayer.get_unique_id()]["nick"]
    rpc("msg_rpc", nick, trimmed_message)
```

## Input Controls

| Key | Action | Purpose |
|-----|---------|---------|
| `Ctrl` | Toggle chat | Show/hide chat interface |
| `Enter` | Send message | Submit current message |
| `Send Button` | Send message | Alternative send method |

## Troubleshooting

### Common Issues

**Chat Not Opening**
- Ensure `toggle_chat` action is mapped to Ctrl key
- Check that `multiplayer_chat` node exists in level scene
- Verify `_input` function is properly connected

**Messages Not Sending**
- Check RPC configuration (`"any_peer", "call_local"`)
- Verify nickname is available in Network.players
- Ensure message validation isn't blocking empty strings

**UI Not Updating**
- Confirm `msg_rpc` RPC is being called
- Check that `add_message` is receiving parameters
- Verify chat TextEdit node is properly referenced

### Debug Logging

Monitor console for chat-related operations:
- Message sending through RPC system
- UI state changes (show/hide)
- Input focus management
- Message validation results

## Performance Considerations

- **Message History**: Automatically limits to 100 messages
- **Network Efficiency**: Uses RPC for lightweight message broadcasting
- **UI Performance**: TextEdit auto-scroll maintains smooth display
- **Memory Management**: Older messages are automatically cleaned up

## Future Extensions

- **Private Messaging**: Direct player-to-player communication
- **Chat Channels**: Separate channels for different purposes
- **Message Filtering**: Content moderation and spam protection
- **Chat Persistence**: Save chat history between sessions
