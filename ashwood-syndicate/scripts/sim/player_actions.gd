class_name PlayerActions
extends RefCounted

## What a candidate — the player or a rival — can do to win someone over.
##
## Every approach resolves through the same machinery as background gossip: the
## act becomes a MemoryToken, the target evaluates it against their own
## psychology, and anyone else in the room witnesses it firsthand.
##
## That leak is the game. A bribe that wins the Merchant's respect in an empty
## market is the same bribe that destroys your standing with the Sheriff if he
## happens to be buying bread at the time.
##
## Rivals use this identical code path, so anything they can do to you, you can
## do to them.

enum Kind { BRIBE, THREATEN, HELP, FLATTER, PROBE, BLACKMAIL, EXPOSE }

## How much of a secret's weight lands on its subject when it is repeated.
const EXPOSURE_FORCE := 10.0

## What carrying tales costs you with the person you tell, scaled by how much
## they value fairness and decency. Gossip is useful and it is not free.
const TALEBEARING_COST := 3.5

## Relationship needed before someone will confide their secret to you.
const PROBE_THRESHOLD := 62.0

## Where a blackmailed target's support is pinned. Above the vote threshold —
## coercion works — but they resent it, and they will try to report it.
const COERCED_SUPPORT := 82.0

## Kind -> { action, severity, label, hint }
const DEFINITIONS := {
	Kind.BRIBE: {
		"key": "B",
		"action": ActionCatalog.BRIBED,
		"severity": 6,
		"label": "Bribe",
		"hint": "Buys the greedy. Outrages anyone who values fairness.",
	},
	Kind.THREATEN: {
		"key": "T",
		"action": ActionCatalog.THREATENED,
		"severity": 7,
		"label": "Threaten",
		"hint": "Fast and loud. Their friends will hear about it.",
	},
	Kind.HELP: {
		"key": "H",
		"action": ActionCatalog.HELPED,
		"severity": 5,
		"label": "Help",
		"hint": "Slow, safe, and it plays well in front of witnesses.",
	},
	Kind.FLATTER: {
		"key": "F",
		"action": ActionCatalog.FLATTERED,
		"severity": 4,
		"label": "Flatter",
		"hint": "Free. Works on vanity. Some people cannot stand it.",
	},
	Kind.PROBE: {
		"key": "P",
		"action": &"",
		"severity": 0,
		"label": "Probe",
		"hint": "Ask what they know. Needs their trust. May uncover a secret.",
	},
	Kind.BLACKMAIL: {
		"key": "K",
		"action": ActionCatalog.BLACKMAILED,
		"severity": 9,
		"label": "Blackmail",
		"hint": "Needs their secret. Buys the vote — until they report you.",
	},
	Kind.EXPOSE: {
		"key": "E",
		"action": &"",
		"severity": 0,
		"label": "Expose",
		"hint": "Tell them what someone else did. Ruins a rival, and costs you.",
	},
}


static func label_for(kind: Kind) -> String:
	return DEFINITIONS[kind]["label"]


static func hint_for(kind: Kind) -> String:
	return DEFINITIONS[kind]["hint"]


## The keyboard shortcut. Stored rather than derived from the label's first
## letter, which silently gave Bribe and Blackmail the same key.
static func key_for(kind: Kind) -> String:
	return DEFINITIONS[kind]["key"]


static func _empty_report(note: String) -> Dictionary:
	return {
		"ok": false, "note": note, "label": "",
		"target_delta": 0.0, "witnesses": [] as Array[StringName], "witness_delta": 0.0,
		"discovered": null,
	}


## Performs `kind` on `target`, in whatever room the target is currently in.
##
## Returns a report: { ok, note, label, target_delta, witnesses, witness_delta,
## discovered }. `ok` is false when the approach could not be attempted, with
## `note` explaining why in the player's language.
## How well an attempt was put, as a multiplier on what it achieves.
##
## `fit` is 0..1 from `IntentReader`: how well-judged the player's actual words
## were for this particular person. Neutral is 0.5, which is what every caller
## that does not have a judgement passes, and which must map to exactly 1.0 so
## the menu path and every balance guard behave as they always did.
##
## **The result is capped at 1.0.** A well-chosen word cannot beat the sim; a
## badly chosen one can lose to it. That asymmetry is not timidity, it is the
## only version that survives contact with `Agent.REPEAT_DECAY`: regard from one
## approach converges on `raw / (1 - decay)`, so any multiplier above 1.0 raises
## the persuasion ceiling by the same proportion. Raise that ceiling and a
## rival's oldest friend becomes winnable by charm alone, which retires Expose,
## the secrets, and the whole leverage half of the game.
##
## What a *well* put line earns instead is elsewhere and deliberate: people are
## more candid with you (`Conversation.candour_threshold`) and less inclined to
## broadcast what you just did (`_spread_to_witnesses`). Both reward reading a
## person without touching the number that holds the design together.
static func delivery_of(fit: float) -> float:
	return clampf(2.0 * clampf(fit, 0.0, 1.0), MIN_DELIVERY, 1.0)


## Floor on delivery, so even the worst-judged line still registers as having
## happened rather than silently doing nothing.
const MIN_DELIVERY := 0.35

## Neutral fit, duplicated from `IntentReader` so the simulation does not depend
## on the dialogue layer.
const NEUTRAL_FIT := 0.5


static func perform(
	kind: Kind,
	target: Agent,
	sim: TownSim,
	day: int,
	actor_id: StringName = Agent.PLAYER_ID,
	subject_id: StringName = &"",
	fit: float = NEUTRAL_FIT
) -> Dictionary:
	if target == null or sim == null:
		return _empty_report("There is nobody to approach.")
	if target.id == actor_id:
		return _empty_report("You cannot campaign against yourself.")

	# Candidates work the room they are standing in. For the player this is the
	# whole reason NPC schedules matter: you have to find people.
	if actor_id == Agent.PLAYER_ID and not sim.player_can_reach(target):
		return _empty_report(
			"%s is at %s. You need to be there." % [
				target.short_name(), TownGrid.zone_name(target.current_zone)
			]
		)

	match kind:
		Kind.PROBE:
			return _probe(target, sim, day, actor_id)
		Kind.BLACKMAIL:
			return _blackmail(target, sim, day, actor_id)
		Kind.EXPOSE:
			return _expose(target, sim, day, actor_id, subject_id)
		_:
			return _approach(kind, target, sim, day, actor_id, fit)


## The four ordinary approaches: an act, evaluated by the target, overheard by
## whoever shares the room.
static func _approach(
	kind: Kind, target: Agent, sim: TownSim, day: int, actor_id: StringName,
	fit: float = NEUTRAL_FIT
) -> Dictionary:
	var definition: Dictionary = DEFINITIONS[kind]
	var token := MemoryToken.new(
		actor_id,
		definition["action"],
		target.id,
		true,
		definition["severity"],
		&"",  # Done in person, so it is firsthand for everyone who sees it.
		day
	)

	# The target experienced it, so it counts every time (with falloff). The
	# room only heard about it, so ordinary belief deduplication applies.
	var target_delta: float = target.receive_approach(token, delivery_of(fit))

	# A deftly put approach is also a quieter one. Fumbling a bribe in a crowded
	# tavern is how the room finds out you are buying votes; putting it well is
	# how you get away with it. This is one of the two places a good line is
	# rewarded, since it cannot be rewarded in regard without raising the
	# ceiling.
	var witness_result: Dictionary = _spread_to_witnesses(token, target, sim, fit)

	EventBus.approach_made.emit(actor_id, kind, target.id, target_delta, witness_result["ids"])

	return {
		"ok": true,
		"note": "",
		"label": definition["label"],
		"target_delta": target_delta,
		"witnesses": witness_result["ids"],
		"witness_delta": witness_result["delta"],
		"discovered": null,
	}


## Asking someone what they know.
##
## Costs nothing and offends nobody, but it only works on people who already
## trust you — which is what stops it being a free opener on the whole town.
static func _probe(target: Agent, sim: TownSim, _day: int, actor_id: StringName) -> Dictionary:
	var trust: float = target.relationships.score_for(actor_id)
	if trust < PROBE_THRESHOLD:
		return _empty_report("%s does not trust you enough to open up." % target.short_name())

	var found: Secret = sim.reveal_secret_of(target.id, actor_id)
	if found == null:
		return _empty_report("%s has nothing left to hide from you." % target.short_name())

	var report: Dictionary = _empty_report("")
	report["ok"] = true
	report["label"] = "Probe"
	report["discovered"] = found

	# A shared secret exposes everyone in it. Getting the Preacher to talk hands
	# you leverage over the Widow as well, without her ever saying a word.
	report["note"] = "%s admits it." % target.short_name()
	if found.participants.size() > 1:
		var partner_id: StringName = found.partner_of(target.id)
		var partner: Agent = sim.agent_by_id(partner_id)
		if partner != null:
			report["note"] = "%s admits it — and it implicates %s." % [
				target.short_name(), partner.short_name()
			]

	# A rival who learns something files it as an ordinary belief too.
	if actor_id != Agent.PLAYER_ID:
		var learner: Agent = sim.agent_by_id(actor_id)
		if learner != null:
			learner.learn(found.content.duplicate_token())

	return report


## Coercion. The strongest single move available, and the riskiest.
##
## It pins the target's support above the vote threshold immediately, but their
## sense of safety collapses and they set off to report it. If they reach the
## Sheriff, what you did becomes public and every moralist in town turns.
static func _blackmail(target: Agent, sim: TownSim, day: int, actor_id: StringName) -> Dictionary:
	if not sim.knows_secret_of(actor_id, target.id):
		return _empty_report("You have nothing to hold over %s." % target.short_name())

	var token := MemoryToken.new(
		actor_id, ActionCatalog.BLACKMAILED, target.id, true,
		DEFINITIONS[Kind.BLACKMAIL]["severity"], &"", day
	)

	var before: float = target.relationships.score_for(actor_id)
	target.relationships.set_score(actor_id, maxf(before, COERCED_SUPPORT))
	target.ledger.record(token)

	# They comply, and they immediately want protection from the person who did
	# this to them.
	target.set_need(Agent.Need.SAFETY, 1.0)
	target.pending_report = token.retold_by(target.id, day)

	var witness_result: Dictionary = _spread_to_witnesses(token, target, sim)

	EventBus.approach_made.emit(
		actor_id, Kind.BLACKMAIL, target.id,
		target.relationships.score_for(actor_id) - before, witness_result["ids"]
	)

	return {
		"ok": true,
		"note": "%s complies — and looks for the Sheriff." % target.short_name(),
		"label": "Blackmail",
		"target_delta": target.relationships.score_for(actor_id) - before,
		"witnesses": witness_result["ids"],
		"witness_delta": witness_result["delta"],
		"discovered": null,
	}


## Repeating what somebody else did.
##
## The counterweight to a relative vote. You cannot out-charm a rival's oldest
## friend — persuasion has a ceiling per person — so the way past a bonded ally
## is to give them a reason to think less of the man they are backing. Without
## this the only lever was raising your own number, and a candidate who started
## with warm ties could not be caught.
##
## It is not free: tale-bearing costs you with people who value fair dealing.
static func _expose(
	target: Agent, sim: TownSim, day: int, actor_id: StringName, subject_id: StringName
) -> Dictionary:
	var chosen: Secret = _pick_exposable(target, sim, actor_id, subject_id)
	if chosen == null:
		return _empty_report("You know nothing about anyone that would interest them.")

	var told: MemoryToken = chosen.content.retold_by(actor_id, day)
	var subject: Agent = sim.agent_by_id(chosen.content.subject_id)
	var subject_name: String = subject.short_name() if subject != null else str(chosen.content.subject_id)

	var damage: float = target.learn(told)
	if is_zero_approx(damage) and target.ledger.knows(told):
		return _empty_report("%s has already heard about %s." % [target.short_name(), subject_name])

	# Everyone in the secret is tarnished, not only the person named in it.
	for participant in chosen.participants:
		if participant == chosen.content.subject_id or participant == target.id:
			continue
		var also: Agent = sim.agent_by_id(participant)
		if also != null:
			target.relationships.adjust(participant, damage * 0.6)

	sim.reveal_secret(chosen, target.id)

	# What it costs you to be the one carrying it.
	var scruples: float = 0.5 * (
		target.psyche.moral_of(Psyche.Foundation.FAIRNESS)
		+ target.psyche.moral_of(Psyche.Foundation.SANCTITY)
	)
	var self_cost: float = target.relationships.adjust(actor_id, -TALEBEARING_COST * scruples)

	EventBus.approach_made.emit(actor_id, Kind.EXPOSE, target.id, self_cost, [] as Array[StringName])

	return {
		"ok": true,
		"note": "%s will not forget that about %s." % [target.short_name(), subject_name],
		"label": "Expose",
		"target_delta": self_cost,
		"witnesses": [] as Array[StringName],
		"witness_delta": damage,
		"discovered": null,
		"subject": chosen.content.subject_id,
	}


## The most damaging thing the actor knows that this listener does not, about
## somebody other than the two of them.
static func _pick_exposable(
	target: Agent, sim: TownSim, actor_id: StringName, subject_id: StringName
) -> Secret:
	var best: Secret = null

	for secret in sim.secrets:
		if not secret.is_known_to(actor_id) or secret.involves(actor_id):
			continue
		if secret.involves(target.id):
			continue  # Nobody needs telling about themselves.
		if subject_id != &"" and secret.content.subject_id != subject_id:
			continue
		if target.ledger.knows(secret.content):
			continue
		if best == null or secret.weight > best.weight:
			best = secret

	return best


## Whether the actor has anything at all worth repeating to this listener.
static func can_expose(target: Agent, sim: TownSim, actor_id: StringName = Agent.PLAYER_ID) -> bool:
	return _pick_exposable(target, sim, actor_id, &"") != null


## Everyone sharing the target's zone saw it happen, and forms their own view.
static func _spread_to_witnesses(
	token: MemoryToken, target: Agent, sim: TownSim, fit: float = NEUTRAL_FIT
) -> Dictionary:
	var ids: Array[StringName] = []
	var total: float = 0.0

	# Discretion runs the other way to delivery: a well-judged line reaches the
	# room *less*. Capped the same way, at the value the menu path has always
	# used, so nothing about witnessing gets easier than it was.
	var discretion: float = clampf(2.0 - 2.0 * clampf(fit, 0.0, 1.0), MIN_DELIVERY, 1.0)

	for observer in sim.agents_in_zone(target.current_zone):
		if observer.id == target.id or observer.id == token.subject_id:
			continue
		var delta: float = observer.witness_approach(token.duplicate_token(), discretion)
		if not is_zero_approx(delta):
			ids.append(observer.id)
			total += delta

	return {"ids": ids, "delta": total}
