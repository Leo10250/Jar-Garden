# Jar Garden — Game Design

## Document Role

This document is the **normative product/design source of truth**: it describes what Jar Garden should feel like and the player-facing rules/direction that implementations should preserve.

It is **not** an implementation-status document. For what exists in code today, use `ARCHITECTURE.md`; for what is completed or next, use `MVP_PLAN.md`; for slow-changing platform constraints, use `PROJECT_CONTEXT.md`.

Values marked TBD remain product decisions even when `prototype_mvp_tuning.tres` or `prototype_content_catalog.tres` contains working prototype values. Prototype Resources are executable balancing inputs, not automatic permanent design commitments.

## 1. High-Level Concept

Jar Garden is a **collection + nurturing + relaxing/healing** game.

The player watches and cares for cute plant-like creatures living inside a glass jar.

These creatures are called plants, but visually they are not ordinary botanical plants.

The basic/common plant is a **small white dumpling/blob-like creature with a cute face**.

Mutations and rarer variants can visually differ through:
- color
- decorations
- headwear
- equipment-like accessories
- combinations of those traits

The game is intentionally low-pressure and built around:

- observing
- caring
- waiting
- discovering
- collecting
- breeding
- seeing unexpected mutations

A central emotional goal is:

> “I did something earlier, came back later, and something cute or surprising happened inside my jar.”

## 2. Core World

The main screen contains a **glass jar**.

The default background/environment is a **forest**.

The environment may present:
- sunlight
- moonlight
- rain
- snow
- other weather later

Long-term, weather may correspond to real-world weather.

The current MVP must not require online weather integration.

## 3. Plant Visual Identity

### Base/Common Plant

The base plant is confirmed to be:

- white
- small
- rounded / dumpling-like / blob-like
- soft and cute in appearance
- has a cute facial expression

The goal is not botanical realism.

It should feel more like a tiny living collectible creature that happens to belong to the game's “plant” ecosystem.

### Expressions

Cute facial expressions are part of the plant identity.

Exact expression set is TBD.

Possible states may later communicate:
- neutral/content
- happy
- sleepy
- uncomfortable
- surprised

These are not finalized mechanics.

Do not implement an expression-state system unless explicitly requested.

### Mutations / Variants

Mutation should be visually rewarding and easy to notice.

Confirmed visual mutation directions:
- body color changes
- decorative items
- headwear
- equipment-like accessories
- combinations of visual changes

For example, a mutation might remain recognizably the same cute blob creature while gaining:
- a different body color
- a leaf/flower/hat-like head decoration
- a tiny wearable or held accessory
- a more unusual overall visual identity

These examples define the direction only.

Exact mutation designs are TBD.

### Important Design Goal

A player should be able to look at a newly born plant and immediately think:

> “This one is different.”

That visible surprise is part of the collection reward.

## 4. Initial State

When a new game starts:

- The player has the default glass jar.
- The default environment is forest.
- The jar contains **5 small plants**.
- The five initial plants are the same base/common type.
- Visually, they are the basic **white cute dumpling/blob plants with faces**.

Minor expression variation may eventually make individuals feel alive, but this is not required for MVP unless explicitly requested.

## 5. Plant Lifecycle

Every plant progresses through:

```text
Young -> Adult -> Old
```

### Young

- Cannot reproduce.
- Can be dragged.
- Grows over real-world time.
- Can be sold for **1 coin**.

### Adult

- Can reproduce.
- Can be sold for meaningful value.
- Sale value depends on rarity/type.
- Has a limited number of reproductions during adulthood.

### Old

- No longer reproduces normally unless later changed.
- Still occupies jar capacity.
- Can be sold for **1 coin**.

Natural death is a possible future feature and not currently required.

Visual differences between young/adult/old are not finalized.

## 6. Dragging Plants

The player can drag plants with a finger.

Dragging matters because position affects:
- how much water a plant receives
- which plants touch
- which adults may reproduce together

Mouse dragging should work during desktop development when practical.

## 7. Watering

The main screen contains a **Water** button.

The player manually adds water from the top of the jar.

Important:
- plants occupy different positions
- different positions can receive different water amounts
- player can water repeatedly
- repeated watering increases wetness
- the jar may become extremely wet or effectively submerged
- water decreases over time

Water exposure can influence:
- plant growth/state
- automatic spawning
- reproduction
- mutation

Exact formulas are TBD.

Do not require realistic fluid physics.

## 8. Sunlight and Moonlight

The game uses device/real-world time to distinguish day/night.

The jar can receive:
- sunlight during the day
- moonlight during the night

Because the container is glass, light is treated as a broad jar/environment influence rather than detailed per-plant shadow simulation.

Light can influence:
- automatic spawning
- reproduction
- mutation
- potentially growth

Exact sunlight-vs-moonlight mechanics are TBD.

## 9. Weather

Long-term states may include:
- sunny
- rainy
- snowy
- other weather

Weather can influence:
- water
- spawning
- growth
- reproduction
- mutation

Eventually this may mirror real-world weather.

For MVP, real weather API integration is deferred.

## 10. Automatic Plant Generation

The jar can naturally produce new young plants over time without two parents.

This is **automatic generation/spawning**.

It may be affected by:
- time
- light
- water
- weather
- environment/background
- randomness

A naturally generated young plant may:
- be the basic/common white plant
- or, at lower probability, be a mutation/variant

Mutation appearance may include:
- different body color
- decoration/headwear
- accessory/equipment-like visual traits

Exact intervals and probabilities are TBD.

### Capacity Rule

When the jar is full:

> No new plants are added through automatic generation.

Maximum capacity is TBD.

## 11. Reproduction

Reproduction is separate from automatic generation.

### Basic Reproduction

Two **adult plants** that are touching can potentially reproduce.

Reproduction:
- takes real-world time
- is not instant
- can be influenced by water
- can be influenced by light
- can be influenced by time/environment

Successful reproduction creates one **young plant**.

### Same-Type Pair

If two touching adult plants are the same type:
- they are more likely to reproduce successfully.

### Offspring

Normally the offspring has a high probability of matching one of its parents.

There is a smaller chance of mutation.

A mutation may express itself visually through:
- color changes
- decorations
- headwear
- accessories/equipment-like traits
- other future visual features

### Reproduction Limit

During adulthood, one plant can reproduce approximately:

**1 to 5 times**

The exact number may vary and is not finalized.

### Mutated Plants

Mutated plants are harder to reproduce.

Possible future representations:
- lower success chance
- longer time
- more demanding environmental requirements

Exact mechanism is TBD.

## 12. Mutation

Mutation is one of the game's main collection mechanics.

A newly spawned or reproduced plant can sometimes become a different variant.

Mutation may be influenced by:
- time
- sunlight
- moonlight
- water exposure
- extreme wetness/submersion
- weather
- environment/background
- parent type
- whether a parent is already mutated
- randomness

The game does **not** need realistic genetics.

The goal is visible, delightful discovery.

### Visual Mutation Philosophy

Mutation should usually have an obvious visual payoff.

Potential dimensions:
- color
- head decoration
- hat/headwear
- wearable item
- equipment-like accessory
- combinations of traits
- other visual motifs later

The exact mapping between environmental conditions and visual mutation traits is TBD.

The exact distinction between “new species” and “visual variant” is also TBD.

Do not build a complex genetics taxonomy yet.

### Possible Discovery Chain

```text
Base white blob
    ->
colored/decorated mutation
    ->
breed/cultivate further
    ->
rarer visual variant
    ->
new collection discovery
```

Exact mutation recipes/probabilities are TBD.

## 13. Collection / Encyclopedia

The game has a plant collection/encyclopedia.

When a plant type/variant is discovered for the first time, it becomes recorded.

The collection may eventually show:
- name
- appearance
- rarity
- description
- discovered/undiscovered state
- visual traits
- other basic information

Undiscovered entries should remain mysterious.

The collection is a major long-term goal.

Because mutations are visually distinct, the encyclopedia should reinforce the pleasure of collecting different-looking blob plants.

## 14. Stall

The main screen contains a **Stall** button.

The stall is the buy/sell area.

### Selling

Young:
- sell for **1 coin**

Adult:
- meaningful value
- value depends on rarity/type/variant

Old:
- sell for **1 coin**

Exact adult prices are TBD.

### Auction

Rare adult plants may eventually be auctionable.

Auction is a future feature and is not required in the first MVP.

## 15. Things the Player Can Buy

### Previously Discovered Plant Young

The player may buy a young version only after that type/variant has already been discovered.

This preserves the importance of first discovery.

The shop may eventually show:
- name
- appearance
- description
- rarity
- price

### Different Jars / Jar Materials

Possible future effects:
- appearance
- capacity
- water behavior
- environmental modifiers
- other effects

Exact effects are TBD.

### Different Backgrounds / Environments

Examples:
- forest
- indoor
- rainforest
- underwater
- others later

Backgrounds may affect:
- light
- weather
- water
- automatic generation
- mutation possibilities

Exact rules are TBD.

## 16. Core Loop

```text
Open the game
    ->
See what changed while away
    ->
Observe growth / aging / new plants
    ->
Check water and environment
    ->
Water if desired
    ->
Drag/reposition plants
    ->
Place desired adults together
    ->
Leave / wait real-world time
    ->
Return later
    ->
Discover growth, reproduction, spawning, or mutation
    ->
Notice a new color/accessory/variant
    ->
Add discovery to collection
    ->
Keep useful plants / sell extras
    ->
Earn coins
    ->
Buy discovered plants, jars, backgrounds, or other content
    ->
Create new environmental conditions
    ->
Discover more variants
```

## 17. Core Experience Principles

### Relaxing

Calm, cute, comfortable.

### Low Interaction, High Observation

Important actions are mainly:
- watering
- dragging
- arranging breeding pairs
- buying/selling

Much of the game happens through time and environment.

### Anticipation

A key question:

> “What will be different next time I open the game?”

### Visual Discovery

A newly mutated plant should be fun to look at.

Color and accessory changes are part of the reward, not merely hidden stats.

### Collection

The player should want to fill the collection with visually distinct plants.

### Environment Matters

Time, water, light, weather, jar, and environment should gradually matter to what appears.

## 18. Most Important Emotional Moment

Target experience:

1. The player places two cute adult blob plants together.
2. The player waters the jar.
3. The game is closed.
4. Real time passes.
5. The player returns.
6. A new young plant has appeared.
7. It has a different color or a cute new decoration/accessory.
8. The player immediately recognizes it as something new.
9. The collection records the discovery.

That surprise is one of the strongest intended rewards.

## 19. Explicitly Undecided Product Values

Do not treat these as finalized:

- maximum jar capacity
- growth durations
- adult lifespan
- automatic-spawn interval
- spawn probabilities
- reproduction duration
- reproduction success probabilities
- mutation probabilities
- mutation recipes
- exact total number of plant types/variants
- exact base silhouette details
- exact face designs
- exact expression system
- exact mutation colors
- exact headwear/accessory/equipment designs
- exact lifecycle visual changes
- exact distinction between species vs mutation vs variant
- adult sale prices
- purchase prices
- jar prices
- background prices
- exact jar effects
- exact background effects
- exact sunlight-vs-moonlight differences
- future weather data source
- auction rules
- natural death behavior

These should remain configurable or be decided later.
