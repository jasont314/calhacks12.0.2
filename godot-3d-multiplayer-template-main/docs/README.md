# Documentation

## Available Documentation

### [Inventory System](inventory-system.md)
Comprehensive guide to the server-authoritative multiplayer inventory system, including:
- Architecture overview and client-server interactions
- RPC methods and server validation
- Usage examples and troubleshooting
- Performance considerations and future extensions

### [Multiplayer Chat System](multiplayer-chat-system.md)
Complete guide to the real-time global communication system, featuring:
- Modular UI design with automatic message formatting
- Client-server RPC communication
- Message history management (100 message limit)
- Input handling and focus management

## Quick Reference

### Key Controls
- `W/A/S/D` - Move character
- `Shift` - Run
- `Space` - Jump
- `Ctrl` - Toggle chat
- `B` - Toggle inventory
- `F1` - Add random test item (debug)
- `F2` - Print inventory contents (debug)
- `Esc` - Quit game

### Main Components

#### **Multiplayer Networking**
- **Server Authority**: Host manages all game state and validates operations
- **ENet Protocol**: Efficient UDP-based networking for real-time gameplay
- **Player Management**: Dynamic player spawning with nickname and skin selection
- **Real-time Sync**: Smooth movement and state synchronization

#### **Inventory System**
- **Server Authority**: All inventory operations validated server-side
- **Client Privacy**: Each player's inventory only syncs with server and owner
- **Real-time UI**: Immediate updates for drag-and-drop and item operations
- **20-Slot Grid**: Organized inventory with item stacking support

#### **Chat System**
- **Global Communication**: Real-time messaging between all connected players
- **Modular Design**: Decoupled UI component for easy integration
- **Auto-focus**: Automatically focuses input when opening chat
- **Message History**: Maintains last 100 messages with automatic cleanup

### Network Flow

#### **Player Connection**
```
Client Connect → Server Validation → Player Spawn → State Sync → UI Update
```

#### **Inventory Operations**
```
Client Request → Server Validation → Server Processing → Client Update → UI Refresh
```

#### **Chat Communication**
```
User Input → Message Validation → RPC Broadcast → All Clients Receive → UI Update
```

## Architecture Overview

### **Core Systems**
- **Network Layer** (`scripts/network.gd`) - Connection management and player info
- **Level Management** (`scripts/level.gd`) - Game state and UI coordination
- **Player Logic** (`scripts/player.gd`) - Character movement and authority
- **Inventory Management** (`scripts/player_inventory.gd`) - Item storage and operations
- **Chat System** (`scripts/multiplayer_chat_ui.gd`) - Communication interface

### **UI Components**
- **Main Menu** (`scenes/ui/main_menu_ui.tscn`) - Connection and setup interface
- **Inventory UI** (`scenes/ui/inventory_ui.tscn`) - Item management interface
- **Chat UI** (`scenes/ui/multiplayer_chat_ui.tscn`) - Communication interface

### **Data Management**
- **Item Database** (`scripts/item_database.gd`) - Centralized item definitions
- **Item Resources** (`scripts/item.gd`) - Item properties and metadata
- **Slot Management** (`scripts/inventory_slot.gd`) - Individual slot operations

## Development Features

### **Debug Tools**
- Multiple instance testing support
- Real-time inventory state monitoring
- Network RPC logging and validation
- Performance metrics and optimization

### **Testing Support**
- Local multiplayer testing with multiple Godot instances
- Debug item addition and inventory manipulation
- Network state inspection and validation
- UI responsiveness and interaction testing

## Getting Started

### **For Developers**
1. Review the architecture documentation for each system
2. Understand the server-authoritative design pattern
3. Familiarize yourself with the RPC communication flow
4. Test with multiple local instances for multiplayer validation

### **For Modders**
1. Extend the item database with new items
2. Modify UI layouts and styling
3. Add new chat features or inventory operations
4. Implement custom player skins and animations

For detailed technical information and implementation examples, see the individual documentation files.
