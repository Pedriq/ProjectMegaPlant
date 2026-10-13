
# Roblox Game Prototype — Cooperative Plant Growth Simulator

## Project Overview

Create a fully playable Roblox Studio prototype for a multiplayer cooperative plant-growing simulator inspired by the shared progression and incremental gameplay of *Build The Pyramid* and the plant-growing loop of *Grow a Garden*.

The game revolves around players working together to grow a giant shared plant. Players collect water, carry it to the plant, and water it to contribute to its growth and earn personal rewards.

**Core design principle:** The plant must grow according to a real-world timer, not solely according to player activity. The plant should continue progressing even when the server is empty, and players should not need to remain online for the plant to mature.

The prototype should be functional, modular, server-authoritative, and easy to expand.

## 1. Existing Assets

Use the existing assets located in these folders:

- Fruit models: `ReplicatedStorage/Aseets/Fruits`
- Watering can models: `ReplicatedStorage/Aseets/WateringCans`

Important: The folder name is spelled `Aseets`, not `Assets`. Use the exact paths.

Before implementing the game:
1. Inspect the contents of both folders.
2. Identify all available fruit and watering can models.
3. Reuse the existing assets instead of creating duplicates whenever possible.
4. Do not assume that every asset has the same name, structure, or primary part.
5. Handle missing or incompatible assets gracefully.
6. If a folder contains multiple fruit models, use them as possible harvest rewards or visual variations.
7. If multiple watering cans are available, use one as the starting tool and leave the others available for future upgrades.

If a required asset is missing, create a simple temporary placeholder using Roblox Parts and clearly separate it from the production asset system.

## 2. Core Gameplay Loop

Implement the following gameplay loop:

1. The player spawns in a shared garden.
2. The player approaches a water source.
3. The player interacts with the water source to fill their watering can.
4. The player carries the water to the giant shared plant.
5. The player waters the plant.
6. The watering action consumes a defined amount of water and awards personal currency or experience.
7. The plant's shared care meter increases.
8. The plant progresses through growth stages according to its persistent timer.
9. When the timer expires, the plant becomes harvestable.
10. Players who qualify for rewards receive harvest rewards.
11. The plant transitions into its next growth cycle.
12. Players spend their earned currency on upgrades that improve their efficiency.

The first prototype should prioritize a polished, reliable version of this loop over a large number of features.

## 3. World Layout

Create a simple, clean, colorful garden environment containing:

- A central giant plant that is visible from most of the playable area.
- One or more water collection stations.
- A clearly defined watering interaction area around the plant.
- A player spawn area.
- A small upgrade shop or upgrade interaction point.
- A basic UI that displays plant progression and player resources.

Use simple geometry and existing assets. The environment should be optimized for multiplayer and mobile devices.

The plant should be large enough to make its growth visually noticeable.

## 4. Water Collection and Watering Mechanics

Implement a functional water-carrying system.

### Water collection
- Players interact with a water source to fill their watering can.
- Each watering can has a configurable water capacity.
- The player cannot collect water beyond the can's capacity.
- The UI displays the current water amount and maximum capacity.
- The system must validate all interactions on the server.

### Watering
- Players can water the plant only when they have water available and are within a valid interaction distance.
- Each successful watering consumes a configurable amount of water.
- Each successful watering increases the plant's shared care meter.
- Each successful watering awards personal currency or experience.
- The server must prevent remote event spam, impossible interaction distances, and duplicated rewards.
- Add a clear visual effect and sound when water is successfully applied.
- Show visible feedback when the player is out of water or too far away.

Use a configurable cooldown to prevent watering exploits and excessive remote requests.

Watering should feel responsive and rewarding, but avoid requiring excessively frequent button presses.

## 5. Shared Plant Growth System

Implement one shared plant for the entire server.

The plant should have the following configurable growth stages:

1. Seedling
2. Young Plant
3. Growing Plant
4. Flowering Plant
5. Mature Plant
6. Harvest Ready

Each stage should have a distinct visual appearance or scale.

If the available fruit assets support it, display fruit on the plant during the later stages. Otherwise, use simple temporary visual placeholders.

### Timer-based growth

The growth system must be independent of server uptime and player activity.

Requirements:

- Store a persistent `GrowthStartTime` timestamp.
- Store the configured cycle duration.
- Calculate the current growth stage using the current server timestamp and the saved growth start timestamp.
- Do not rely on a loop that counts elapsed seconds only while the server is running.
- If the server shuts down or restarts, restore the correct growth stage when a new server starts.
- If the plant matures while no players are online, it should still be mature when players return.
- Do not reset the growth timer simply because a player leaves.
- Do not accelerate the timer automatically based on the number of players online.

For the initial prototype, use a configurable cycle duration of 10 minutes. Make it easy to change this value in a central configuration module.

Use `Workspace:GetServerTimeNow()` or an equivalent authoritative timestamp for live server calculations, with persisted timestamps used to restore progress across server sessions.

If a plant has already matured, it should remain harvestable until the next cycle begins.

### Shared care meter

Implement a shared care meter that increases when players water the plant.

The care meter should influence the quality or bonus value of the harvest, but it must not prevent the basic harvest from becoming available when the timer expires.

For example:
- Low care: basic harvest rewards.
- Medium care: additional currency.
- High care: additional currency and a chance for a bonus fruit.

Use configurable thresholds and rewards.

The care meter should reset according to the configured cycle rules when a new growth cycle begins.

## 6. Harvest and Reward System

When the growth timer expires:

- Change the plant's state to `HarvestReady`.
- Update the UI to indicate that the plant is ready.
- Trigger a noticeable visual effect.
- Allow players to interact with the plant to claim harvest rewards.
- Award each eligible player only once per cycle.
- Use a unique cycle identifier to prevent duplicate claims.
- Do not let players repeatedly claim rewards by leaving and rejoining.
- Do not allow clients to decide reward amounts or eligibility.

For the prototype, eligibility should be based on meaningful contribution during the current cycle.

Use a configurable minimum contribution threshold. Players who meet the threshold can claim the full personal harvest reward, while the shared plant still matures regardless of participation.

New players should be able to participate in the next cycle without being permanently disadvantaged.

After the harvest phase ends, automatically start the next growth cycle and persist its new start timestamp.

Use a configurable harvest window, initially set to 2 minutes. If no eligible player claims a reward during that window, the next cycle should still start normally. The system must not become stuck waiting for players.

Make the harvest interaction clear and easy to understand.

## 7. Personal Progression and Upgrades

Implement a basic currency system.

Players earn currency by watering the plant and claiming harvest rewards.

Add at least three functional upgrades:

### Upgrade 1: Water Capacity
Increases the amount of water the player can carry per trip.

### Upgrade 2: Movement Speed
Slightly increases the player's movement speed, within reasonable limits.

### Upgrade 3: Watering Efficiency
Increases the amount of care or contribution generated by each successful watering, within a configurable cap.

Requirements:
- Display upgrade prices.
- Validate purchases on the server.
- Deduct currency only after validating the transaction.
- Prevent duplicate purchases and negative balances.
- Update the player's stats and UI immediately.
- Save upgrade levels between sessions.

Use a simple upgrade shop interface that works on desktop and mobile.

## 8. User Interface

Create a clean, readable UI with a colorful garden aesthetic.

The main HUD should display:

- Current currency.
- Current water amount and watering can capacity.
- Plant growth stage.
- Time remaining until harvest.
- Shared care meter.
- Current personal contribution.
- A brief contextual interaction prompt.

When the plant becomes harvestable, display a clear notification.

When a player earns currency or contributes to the plant, provide immediate visual feedback.

Add a small upgrade menu with prices and current upgrade levels.

UI requirements:
- Use Roblox's standard UI components.
- Use scalable layouts and appropriate anchors.
- Support desktop, tablet, and mobile screens.
- Avoid excessive UI elements covering the gameplay area.
- Do not depend exclusively on hover interactions.
- Keep text readable at small screen sizes.

## 9. Multiplayer and Server Architecture

Use a server-authoritative architecture.

The client may request actions, but the server must validate and execute all important gameplay logic.

Use:
- `ServerScriptService` for server gameplay logic.
- `ReplicatedStorage` for shared configuration, shared modules, and RemoteEvents or RemoteFunctions.
- `StarterPlayer` or `StarterGui` for client controllers and UI.
- `Workspace` for the world, plant, water stations, and interaction points.

Separate the code into modular systems where practical:

- `PlantGrowthService`
- `WateringService`
- `WaterSourceService`
- `HarvestService`
- `PlayerDataService`
- `UpgradeService`
- `UIController`

These may be implemented as ModuleScripts with server-side responsibilities separated from client presentation.

Do not place authoritative reward calculations, currency changes, contribution values, or harvest eligibility checks in LocalScripts.

Validate:
- Interaction distance.
- Water availability.
- Cooldowns.
- Water capacity.
- Player contribution.
- Upgrade affordability.
- Harvest eligibility.
- Duplicate reward claims.
- Data persistence and cycle transitions.

Use RemoteEvents for client requests and server-to-client notifications. Never trust client-supplied currency, contribution, growth stage, or reward amounts.

## 10. Data Persistence

Use `DataStoreService` to persist player progression and shared plant state.

### Player data
Save:
- Currency.
- Upgrade levels.
- Total contribution.
- Other necessary progression data.

### Shared plant data
Persist:
- Growth cycle identifier.
- Growth start timestamp.
- Current care meter.
- Growth cycle configuration version, if needed.
- Harvest state or other data required to restore the correct lifecycle.

If contribution and reward eligibility must survive server restarts, persist per-cycle contribution data or another reliable representation of eligible players.

Requirements:
- Use `pcall` around data store operations.
- Handle failed reads and writes safely.
- Use `UpdateAsync` when appropriate for shared state updates.
- Avoid saving every frame or every watering action unnecessarily.
- Use periodic saves and save on player departure where appropriate.
- Handle `PlayerRemoving` and `BindToClose`.
- Do not overwrite valid saved data with default values after a failed load.
- Use session locking or another concurrency-safe strategy where needed.
- Prevent multiple servers from independently issuing conflicting harvest rewards for the same shared cycle.

For a prototype, use the simplest robust implementation possible, but do not fake persistence with in-memory variables alone.

If DataStore access is unavailable in Studio, provide a clearly documented Studio testing mode and instructions for enabling API services.

## 11. Visual Feedback and Polish

The prototype should feel playable rather than like a collection of debug scripts.

Include:
- Visible water collection feedback.
- A watering animation or temporary water stream effect.
- Water droplets or particles when watering.
- Plant scaling or model transitions between growth stages.
- A noticeable harvest-ready effect.
- Floating currency or contribution feedback.
- Basic sound effects where appropriate.

Use existing assets from the specified folders wherever possible.

Do not assume a fruit model is automatically a complete plant model. Inspect the model hierarchy and build a compatible presentation around the actual available assets.

Keep visual effects lightweight and optimized for Roblox multiplayer.

## 12. Configuration

Create a central configuration module containing tunable values such as:

- Growth cycle duration.
- Harvest window duration.
- Water capacity.
- Water consumed per watering.
- Water collection cooldown.
- Watering cooldown.
- Currency rewards.
- Contribution per watering.
- Care meter thresholds.
- Upgrade prices and effects.
- Minimum contribution required for harvest eligibility.
- Maximum watering efficiency.
- Visual growth stage thresholds.

Avoid scattering gameplay constants across multiple scripts.

## 13. Error Handling and Testing

Implement and test the following scenarios:

1. A new player joins an empty server.
2. A player collects water and waters the plant.
3. A player attempts to water the plant without water.
4. A player tries to water from outside the valid interaction distance.
5. A player attempts to spam watering requests.
6. Several players water the plant simultaneously.
7. A player leaves and rejoins.
8. The server restarts during plant growth.
9. The plant matures while the server is empty.
10. The plant becomes harvestable with zero care contributions.
11. Two players attempt to claim the same cycle reward simultaneously.
12. A player attempts to claim a reward more than once.
13. A player tries to purchase an upgrade without sufficient currency.
14. A data store operation fails.
15. A player joins during an existing growth cycle.
16. The harvest window expires without any claims.
17. A fruit or watering can asset is missing or incompatible.

Fix all obvious errors and ensure the main loop works in a multiplayer Studio test with at least two players.

## 14. Deliverables

Produce a working Roblox Studio implementation, not just pseudocode or a design document.

Deliver:
1. A complete Explorer hierarchy.
2. All required Scripts, LocalScripts, and ModuleScripts.
3. All required RemoteEvents and RemoteFunctions.
4. A functional garden environment.
5. A working shared plant growth system.
6. A working water collection and watering system.
7. A functional timer-based harvest and reward system.
8. A basic upgrade shop.
9. Data persistence with error handling.
10. A brief setup guide describing where every script and asset belongs.
11. Testing instructions and any Studio configuration requirements.

If you can directly modify the Roblox Studio project, create the required instances and scripts in the project.

If direct project editing is unavailable, provide the complete source code for each script, label each code block with its exact Roblox Explorer path, and explain how to assemble the project. Do not claim that files or instances have been created unless they actually have been.

## 15. Implementation Priorities

Work in this order:

**Priority 1:** Functional water collection, watering, and shared plant growth.

**Priority 2:** Persistent timer, harvest transitions, and duplicate-reward protection.

**Priority 3:** Personal currency, contribution tracking, and upgrades.

**Priority 4:** UI, visual effects, and polish.

**Priority 5:** Multiplayer edge cases, data persistence validation, and optimization.

First inspect the existing assets and project structure. Then implement the minimum complete playable version, test the core gameplay loop, and fix any errors before adding optional features.

Do not add unnecessary systems such as pets, trading, complex crafting, or monetization until the core gameplay loop is stable.

**Final acceptance criterion:** Two or more players must be able to join the same server, collect water, contribute to a shared plant, observe timer-based growth, leave and rejoin without resetting the plant, and receive valid rewards without duplicate claims. The plant must also mature correctly when no players are online, and the next server must restore its correct state.