class_name Agent
extends RefCounted

## One simulated inhabitant, with no dependency on the scene tree.
##
## Everything that decides behaviour lives here: psychology, beliefs,
## relationships, needs and schedule. The `Npc` node owns an Agent and is
## responsible only for drawing it and moving it across the grid.
##
## The split exists so the whole 7-day simulation can run headless in a unit
## test — no viewport, no frames, no rendering.

## Drives when an NPC abandons their schedule to go find someone.
enum Need { SAFETY, MONEY, RESPECT, BELONGING }

## Need level at which the NPC overrides their daily schedule to act.
const SEEK_THRESHOLD := 0.8

var psyche: Psyche
var ledger: MemoryLedger
var relationships: RelationshipBook
var schedule: Schedule

## Need -> 0.0..1.0
var needs: Dictionary = {}

## Zone the agent currently occupies.
var current_zone: int = TownGrid.Zone.RESIDENCES

## When non-empty, the agent has abandoned their schedule to hunt this id down.
var seeking_target: StringName = &""

## The town's web of ties, shared by every agent. Null for a bare agent built in
## a unit test, in which case attachment falls back to the psyche's own arrays.
var relations: RelationGraph

## Something this agent is rushing to tell whoever they are seeking. Delivered
## on arrival, which is how a blackmail victim reaches the Sheriff.
var pending_report: MemoryToken


func _init(p_psyche: Psyche, p_schedule: Schedule = null) -> void:
	psyche = p_psyche
	ledger = MemoryLedger.new()
	relationships = RelationshipBook.new()
	schedule = p_schedule if p_schedule != null else Schedule.default_schedule()

	for n in Need.values():
		needs[n] = 0.0

	# Neuroticism is a standing anxiety floor, not just a reaction multiplier.
	needs[Need.SAFETY] = psyche.trait_of(Psyche.Trait.NEUROTICISM) * 0.3


var id: StringName:
	get:
		return psyche.id


var display_name: String:
	get:
		return psyche.display_name


## What the town calls them, for map labels and log lines.
func short_name() -> String:
	return psyche.short_name


## Strength of tie between this agent and `other_id`, in -1.0 .. 1.0.
##
## Positive means harm to them wounds this agent and their wrongdoing gets
## excused; negative means the reverse. Reads the relation graph when there is
## one, and otherwise falls back to the psyche's declared attachments, so an
## agent constructed on its own still behaves sensibly.
func attachment_to(other_id: StringName) -> float:
	if relations != null:
		var tie: float = relations.attachment(id, other_id)
		if not is_zero_approx(tie):
			return tie

	if psyche.loyal_to.has(other_id):
		return DECLARED_ATTACHMENT
	if psyche.rivals.has(other_id):
		return -DECLARED_ATTACHMENT
	return 0.0


## Strength given to a bare `loyal_to` / `rivals` entry with no typed tie behind
## it. Chosen so the older flat declarations keep producing exactly the
## reactions they always did.
const DECLARED_ATTACHMENT := 0.8


func need_of(n: Need) -> float:
	return needs.get(n, 0.0)


func set_need(n: Need, value: float) -> void:
	needs[n] = clampf(value, 0.0, 1.0)


func raise_need(n: Need, amount: float) -> void:
	set_need(n, need_of(n) + amount)


## The zone this agent should be in right now, unless they are seeking someone.
func intended_zone(hour: int) -> int:
	if is_seeking():
		return current_zone
	return schedule.zone_at(hour)


func is_seeking() -> bool:
	return seeking_target != &""


func begin_seeking(target_id: StringName) -> void:
	if seeking_target == target_id:
		return
	seeking_target = target_id
	EventBus.seeking_started.emit(id, target_id)


func stop_seeking() -> void:
	seeking_target = &""


## Whether any need has crossed the threshold that overrides the daily routine.
func has_urgent_need() -> bool:
	for n in Need.values():
		if need_of(n) >= SEEK_THRESHOLD:
			return true
	return false


## The most pressing need. Ties resolve by enum order for determinism.
func dominant_need() -> Need:
	var best: Need = Need.SAFETY
	var best_value: float = -1.0
	for n in Need.values():
		var value: float = need_of(n)
		if value > best_value:
			best_value = value
			best = n
	return best


## Files a belief and applies its relationship consequences.
##
## Returns the relationship delta that was applied toward the token's subject.
## Zero means the claim was already known and correctly had no further effect.
func learn(token: MemoryToken) -> float:
	if not ledger.record(token):
		return 0.0

	var delta: float = GossipEngine.evaluate(token, self)
	if is_zero_approx(delta):
		return 0.0

	var applied: float = relationships.adjust(token.subject_id, delta)
	if not is_zero_approx(applied):
		EventBus.relationship_changed.emit(id, token.subject_id, applied)
	return applied


## How fast a repeated approach loses its power: each repetition is worth this
## fraction of the one before.
##
## Geometric, not harmonic. A 1/(1+kn) falloff still diverges, so with enough
## hours every inhabitant reached the 100 ceiling for every candidate and the
## election decayed into a tie nobody could lose. Geometric decay caps the total
## a single tactic can ever earn at about 1/(1-decay) times its first use, which
## forces variety instead of repetition.
##
## The exact value is load-bearing. At 0.55 the ceiling on one person sat around
## 72 regard, which is *below* the 74 that a plain friendship opens at — so a
## rival's oldest friend was mathematically unwinnable no matter how well the
## player played. Both balance guards are sensitive to this number.
const REPEAT_DECAY := 0.72

## action -> how many times it has been done to this agent in person.
var _direct_action_counts: Dictionary = {}


## Something a candidate did to this agent, face to face.
##
## Distinct from `learn()` on purpose. `learn()` deduplicates, because hearing
## the same rumour from five people is one belief — but a second genuine favour
## is a second genuine favour. Without this split, every inhabitant could be
## influenced exactly once per approach type and the election was unwinnable.
##
## Repeats still decay, so nobody can be farmed with the same gesture forever.
## The count is per actor as well as per action, so a rival's flattery does not
## blunt the player's.
##
## `delivery` is how well the attempt was put, from `PlayerActions.delivery_of`.
## It is at most 1.0 by design — see that function for why a bonus would quietly
## dismantle the game.
func receive_approach(token: MemoryToken, delivery: float = 1.0) -> float:
	var key: StringName = StringName("%s|%s" % [token.subject_id, token.action])
	var count: int = _direct_action_counts.get(key, 0)
	_direct_action_counts[key] = count + 1

	var raw: float = GossipEngine.evaluate(token, self)
	var falloff: float = pow(REPEAT_DECAY, float(count))

	# Delivery has to be applied with the sign in mind, and getting this wrong is
	# silent. A clumsy bribe evaluates *negative* — it offends — so scaling that
	# down by delivery made a badly judged bribe offend less, and fumbling an
	# approach became the safest way to attempt it. A poor line must earn less
	# when it would have gained, and cost more when it would have lost.
	var scaled: float = raw * falloff
	scaled *= delivery if scaled > 0.0 else 2.0 - delivery

	var applied: float = relationships.adjust(token.subject_id, scaled)

	# They remember it happened, which is what the LLM prompt will draw on and
	# what they can pass along as gossip later.
	ledger.record(token)

	if not is_zero_approx(applied):
		EventBus.relationship_changed.emit(id, token.subject_id, applied)
	return applied


## How many times `actor_id` has done `action` to this agent in person.
func times_received(action: StringName, actor_id: StringName = &"player") -> int:
	return _direct_action_counts.get(StringName("%s|%s" % [actor_id, action]), 0)


## Seeing something done to somebody else counts for less than having it done
## to you.
const WITNESS_WEIGHT := 0.7

## How fast repeatedly watching the same person do the same thing stops
## registering.
const WITNESS_DECAY := 0.5

## actor|action -> how many times this agent has watched it happen to others.
var _witness_counts: Dictionary = {}


## Something this agent saw a candidate do to somebody else.
##
## Needs its own decay, separate from belief deduplication. Each act has a
## different victim, so every one is a genuinely new claim and `learn()` applied
## it in full — which meant a candidate could stand in a crowded tavern doing
## favours all week and drive the entire room to maximum regard. Watching the
## same person do the same thing repeatedly stops being informative long before
## that.
## `discretion` is how much of the act reached the room, from
## `PlayerActions._spread_to_witnesses`. At most 1.0, so a clumsy line can leak
## no worse than the menu path always did.
func witness_approach(token: MemoryToken, discretion: float = 1.0) -> float:
	if not ledger.record(token):
		return 0.0

	var key: StringName = StringName("%s|%s" % [token.subject_id, token.action])
	var count: int = _witness_counts.get(key, 0)
	_witness_counts[key] = count + 1

	var raw: float = GossipEngine.evaluate(token, self)
	var scale: float = WITNESS_WEIGHT * pow(WITNESS_DECAY, float(count)) * discretion
	var applied: float = relationships.adjust(token.subject_id, raw * scale)

	if not is_zero_approx(applied):
		EventBus.relationship_changed.emit(id, token.subject_id, applied)
	return applied


## Relationship with the player, the number the endgame vote reads.
func opinion_of_player() -> float:
	return relationships.score_for(Agent.PLAYER_ID)


const PLAYER_ID := &"player"
