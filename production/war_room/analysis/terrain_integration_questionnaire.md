# Terrain Integration Questionnaire
**Purpose:** Establish clarity on TerrainEngine integration before implementation
**Date:** 2026-05-26
**Fill out and return to War Room**

---

## SECTION 1: TerrainEngine Identity

The TerrainEngine should remain a **reusable module** that could power other games. This means game-specific logic (firebase construction, VC tunnels, etc.) should live *outside* the engine, querying it through clean interfaces.

### 1.1 What should TerrainEngine OWN (be the authority on)?

Check all that apply:

- [x ] Heightmap data (elevation at any point)
- [x ] Chunk loading/streaming
- [x ] Vegetation presence (is there a tree here?)
- [x ] Vegetation density (jungle/sparse/cleared)
- [x ] Ground material (dirt, mud, water, rock)
- [ x] Passability (can units walk here?)
- [x ] Cover values (how much concealment does this cell provide?)
- [x ] Road network (paths carved into terrain)
- [x ] Water bodies (rivers, paddies, swamps)
- [ ] Other: _______________

### 1.2 What should TerrainEngine EXPOSE but not own?

These are things game systems tell terrain about, and terrain tracks:

- [ ] Building footprints (construction tells terrain "I built here")
- [ x] Clearing state (JUNGLE → CLEARED progression)
- [ x] Damage/scarring (craters, napalm burns)
- [ x] Tunnel entrances (VC system registers locations)
- [x ] LZ status (helicopter system marks landing zones)
- [ ] Other: _______________

### 1.3 What should stay OUTSIDE TerrainEngine entirely?

- [ ] Building logic (what can be built, construction stages)
- [ ] Job/worker system
- [ ] Combat resolution
- [ ] Unit pathfinding (queries terrain but owns decisions)
- [ ] Firebase zone management
- [ ] Supply chain logic
- [ ] Other: _well this is where my question stands, wouldnt it be easier to make all of these things derive from the terrain since its the most important part of the game? there where my lack of game design knowledge and how really code workss can be broken. but i do know you dont build a house with a load bearing beam with everything with the house ontop of it. 

## SECTION 2: Dynamic Terrain Features

### 2.1 Current dynamic terrain features (check if implemented):

| Feature | Implemented? | Causing Issues? | Keep/Cut/Defer? |
|---------|--------------|-----------------|-----------------|
| Jungle clearing (bulldozer/det-cord) | Should be there
| Tree felling (individual trees) | Should be there
| Weapon scarring (craters) | should be apart of the terrain system shouldn't it?
| Napalm burn marks | part of the terrain as well 
| Road carving | should be apart of the game and again would be helpful if the terrain engine was making this no?
| Trench digging should be apart of the game and would help if the terrain helps us with this. 
| Flooding/water level changes | i haven't seen any water in the game but we should have it
| Vegetation regrowth | no vegetation regrowth

### 2.2 Which dynamic features are CORE to the Vietnam fantasy?

(Rank 1-3: 1 = Essential, 2 = Nice to have, 3 = Cut for MVP)

- [1 ] ___ Jungle clearing (carve the map)
- [1 ] ___ Road building
- [ 1] ___ Weapon craters
- [1 ] ___ Napalm scars
- [ 1] ___ Tree destruction from combat
- [ ] ___ Other: _______________

### 2.3 Suspected crash sources:

Describe the test scene crashes:

**When do crashes happen?**
- [x ] On scene load
- [x ] After X minutes of play
- [ ] When performing specific action: _______________
- [ ] Randomly
- [ ] When many units present
- [x ] When vegetation is dense
- [ ] Other: _______________

**Error messages (if any):**
```
(paste any error output here)
```

**What's in the test scene when it crashes?**
- Approximate unit count: ___
- Vegetation density: [ ] High [ ] Medium [ ] Low
- Active systems: _______________

---

## SECTION 3: Performance Constraints

### 3.1 Your development machine:
just look into the computer systems and find out. 

- CPU: _______________
- RAM: ___ GB
- GPU: _______________
- Godot version: 4.6

### 3.2 Target minimum specs for players:

- CPU: _______________
- RAM: ___ GB
- GPU: _______________

### 3.3 Current performance observations:

| Scenario | FPS | Notes |
|----------|-----|-------|
| Empty terrain | ___ | |
| Terrain + vegetation | ___ | |
| Terrain + 50 units | ___ | |
| Terrain + 200 units | ___ | |
| Firebase construction | ___ | |
| Combat with effects | ___ | |

### 3.4 What's the acceptable minimum FPS?

- [x ] 60 FPS (smooth)
- [ ] 30 FPS (playable)
- [ ] Variable is okay as long as no crashes

---

## SECTION 4: Integration Holes

### 4.1 Where do you see systems "fighting"?

Describe specific friction points you've noticed:

1. when making new scenes the ai keeps spawning things on different levels and even earlier in the development we were fighting with the clear grid for the forest etc
2. pathfinding and random terrain spikes resulting from jobs of contruction or clearing etc. I havent really seen small surgical flattening of areas for building but the newest fix was showing holes being dug around blueprint areas than no job was being worked on. 
3.I haven't even gotten much further than that. units seem to be fine going around the terrain so im not worried about that but haven't been able to test much else because ive been going in circles with the clearing construction loop. 

### 4.2 What questions does construction need to ask terrain?

Example: "Is this cell cleared enough to build?"

The three questions is, can the model make its way to the blueprint? if not than it will clear its way through trees to get there in the fastest straightest path i can take, looking for other cut paths that might exist somehwere else that would have an even shorter distance if possible. than if theres a tree in place of where the building will be. if not is the terrain for the model blueprint flattened enough to not make the building sit weird on the terrain. but with that if we have to bend a bit and make that not a thing than lets explore it. and than finally the building is made. 

### 4.3 What questions does terrain need to answer for ANY game using it?

(These become the engine's public API)

1. _Where am I at? whats the current biome im in look like?______________
2. __a sense of north east south west that stays consistent when talking to other systems so true understanding is there. 
3. not sure what else it could. 

---

## SECTION 5: The Path Forward

### 5.1 Preferred approach:

- [ ] **Stabilize First**: Fix crashes and current issues, document integration points, defer refactor
- [ ] **Interface First**: Define clean TerrainEngine API, migrate systems incrementally
- [ x] **Rewrite Core**: Rebuild construction/jobs with terrain as authority (high risk, high reward)

### 5.2 What's your timeline pressure?

- [ ] No deadline, quality over speed
- [ ] Want playable demo by: _______________
- [x ] Specific milestone: I want to be at the same state we are at if not further with this rewrite and ill call that a milestone. 

### 5.3 What would "working" look like for the next session?

Describe a concrete test you'd want to pass:

```
Example: "I can drag-paint sandbags along a jungle edge,
engineers auto-build them, and no phantom trees appear"
```

Your test:
```
A true pass is units spawning on a somewhat hilly small stretch of land with a small TOC and firebase elements there. i can get my units to move around and build sandbags and bunkers that all face the appropriate directions as I place them and than have a wave of vc units attack the fort and prove the whole loop of clearing construction defense is there. 

```

---

## SECTION 6: Immediate Actions

### 6.1 Before any architecture work, should we:

- [ ] Revert all changes from today's failed fix attempt
- [ ] Run the game in current (broken?) state to catalog errors
- [ x] Profile performance to identify actual bottlenecks
- [x ] Audit which systems touch terrain data

### 6.2 Files you suspect are problematic:

1. something with the construction orientation, the grids maybe? it could be locking the models up 
2. the terrainheights and dynamic terrain isn't matching with what i want sometimes. like i said im notcing units are digging a hole when they start making a sandbag than they stop. other units seem to get stuck on the hole. 


### 6.3 Reference files status:

The files in `C:\Users\caleb\Downloads\files` - are these:
- [ ] From a different branch/version of the game
- [ ] A refactored version you want to adopt
- [ ] Someone else's implementation
- [ ] Your own earlier work
- [ ] Other: plans i got from claude code online that did a deeper dive on CoH game sandbags. 

---

## NOTES

Add any other context, frustrations, or ideas here:

```
I just wanna make a really awesome RTS game and I just never thought making one would be this hard. im sure theres more resources we could find online that could help guide us. i know theres that godot rts plugin maybe we should look into what we can learn from that as well as try hard to crack some more of the company of hero architecture as well as supremem commander and really any rts of worth. 



```

---

*Return this to the War Room when complete. The Council will reconvene with your answers.*
