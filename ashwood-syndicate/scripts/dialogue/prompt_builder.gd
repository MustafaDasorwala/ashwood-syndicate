class_name PromptBuilder
extends RefCounted

## Turns simulation state into a character prompt.
##
## Two rules shape everything here:
##
## 1. **The outcome is given, not asked for.** The prompt tells the model what
##    already happened and asks it to say that in character. Asking a model to
##    judge produced empty output on small models and let it contradict the
##    simulation on large ones.
## 2. **The budget is small.** Only the handful of beliefs an NPC would actually
##    bring up goes in, because the same prompt has to fit a 3B model on a phone
##    later. `MemoryLedger.most_significant` exists for exactly this.

## Beliefs included in a prompt. Enough to be pointed, small enough to be cheap.
const MEMORY_BUDGET := 4


## Builds the request handed to a `DialogueBackend`.
##
## `outcome` is one of: greeting, hostile, warm, guarded, reveal, refuse.
static func build(
	speaker: Agent,
	sim: TownSim,
	outcome: String,
	player_line: String = "",
	topic: String = "",
	history: Array[Dictionary] = []
) -> Dictionary:
	return {
		"speaker_id": speaker.id,
		"speaker_name": speaker.short_name(),
		"outcome": outcome,
		"topic": topic,
		"player_line": player_line,
		"system": _character_sheet(speaker, sim, history),
		"instruction": _instruction(speaker, outcome, topic),
	}


## A short read on who this person is, for `IntentReader` to judge how well a
## line suits them.
##
## Deliberately not the full sheet: the reader must not be told what they are
## hiding. It is judging phrasing, and a model that knows the secret starts
## scoring "did they guess right" instead.
static func persona_summary(speaker: Agent) -> String:
	var lines: Array[String] = []
	lines.append("WHO THEY ARE: %s" % _describe_character(speaker.psyche))
	lines.append("WHAT THEY HOLD SACRED: %s" % _describe_morals(speaker.psyche))
	if speaker.psyche.trauma_trigger != &"":
		lines.append("WHAT THEY CANNOT BEAR: being %s." % speaker.psyche.trauma_trigger)
	lines.append("HOW THEY REGARD THE SPEAKER: %s" % _describe_regard(speaker.opinion_of_player()))
	return "\n".join(lines)


## The persona. Written as prose rather than numbers — models hold character far
## better from "you obey the law even when it is cruel" than from "authority:
## 0.95".
static func _character_sheet(speaker: Agent, sim: TownSim, history: Array[Dictionary] = []) -> String:
	var psyche: Psyche = speaker.psyche
	var lines: Array[String] = []

	lines.append("You are %s, an inhabitant of Ashwood, a secluded frontier town." % speaker.display_name)
	lines.append("The old leader is dead. In seven days the town votes on a successor.")
	lines.append("")
	lines.append("WHO YOU ARE: %s" % _describe_character(psyche))
	lines.append("WHAT YOU HOLD SACRED: %s" % _describe_morals(psyche))

	var ties: String = _describe_ties(speaker, sim)
	if ties != "":
		lines.append("WHO MATTERS TO YOU: %s" % ties)

	var hiding: String = _describe_secrets(speaker, sim)
	if hiding != "":
		lines.append("WHAT YOU HIDE: %s You will not volunteer this." % hiding)

	if psyche.trauma_trigger != &"":
		lines.append("WHAT YOU CANNOT BEAR: being %s. It bypasses your reason entirely." % psyche.trauma_trigger)

	var beliefs: String = _describe_beliefs(speaker)
	if beliefs != "":
		lines.append("WHAT YOU BELIEVE ABOUT THE PERSON IN FRONT OF YOU: %s" % beliefs)

	lines.append("HOW YOU FEEL ABOUT THEM RIGHT NOW: %s" % _describe_regard(speaker.opinion_of_player()))

	# Without the recent exchange the model answers every line as though it were
	# the first thing anyone had said, which is survivable in a three-line menu
	# and falls apart the moment the player can actually hold a conversation.
	var said: String = _describe_history(history)
	if said != "":
		lines.append("")
		lines.append("WHAT HAS ALREADY BEEN SAID, oldest first:")
		lines.append(said)

	lines.append("")
	lines.append("RULES: You are this character. Never break character, never mention being an AI.")
	lines.append("Speak 1-2 sentences, no more. Plain speech, no stage directions, no quotation marks.")
	lines.append("Do not repeat a greeting you have already given, and do not repeat yourself.")

	return "\n".join(lines)


static func _describe_history(history: Array[Dictionary]) -> String:
	if history.is_empty():
		return ""
	var parts: Array[String] = []
	for entry in history:
		parts.append("%s: %s" % [entry.get("speaker", "?"), entry.get("line", "")])
	return "\n".join(parts)


## What the model is being asked to say, given that the sim already decided it.
static func _instruction(speaker: Agent, outcome: String, topic: String) -> String:
	match outcome:
		"greeting":
			return "They have just approached you. Greet them the way you would."
		"hostile":
			return "You are angered by what they just said. Rebuff them."
		"warm":
			return "What they said landed well. Respond with guarded warmth — you are still %s." % speaker.short_name()
		"guarded":
			return "What they said neither helped nor hurt. Answer without giving ground."
		"reveal":
			return "You trust them enough to share what you know about %s. Tell them, reluctantly." % topic
		"refuse":
			return "You do not trust them enough to discuss %s. Deflect without admitting there is anything to tell." % topic
		_:
			return "Respond in character."


static func _describe_character(psyche: Psyche) -> String:
	var parts: Array[String] = []
	var t := Psyche.Trait

	parts.append("guarded and anxious" if psyche.trait_of(t.NEUROTICISM) > 0.6 else "steady")
	if psyche.trait_of(t.EXTRAVERSION) > 0.7:
		parts.append("talkative, you enjoy an audience")
	elif psyche.trait_of(t.EXTRAVERSION) < 0.3:
		parts.append("withdrawn, you say as little as possible")
	if psyche.trait_of(t.AGREEABLENESS) < 0.35:
		parts.append("blunt to the point of rudeness")
	if psyche.trait_of(t.CONSCIENTIOUSNESS) > 0.7:
		parts.append("rigid about duty and order")
	if psyche.dark_of(Psyche.Dark.MACHIAVELLIANISM) > 0.6:
		parts.append("you read every conversation for advantage")
	if psyche.dark_of(Psyche.Dark.NARCISSISM) > 0.5:
		parts.append("vain, and easily flattered")

	return ", ".join(parts) + "."


static func _describe_morals(psyche: Psyche) -> String:
	const NAMES := {
		Psyche.Foundation.CARE: "protecting people from harm",
		Psyche.Foundation.FAIRNESS: "fairness and honest dealing",
		Psyche.Foundation.LOYALTY: "loyalty to your own",
		Psyche.Foundation.AUTHORITY: "law, order and proper authority",
		Psyche.Foundation.SANCTITY: "purity and decency",
	}
	return NAMES.get(psyche.highest_foundation(), "your own counsel")


static func _describe_ties(speaker: Agent, sim: TownSim) -> String:
	if sim == null or sim.relations == null:
		return ""

	var parts: Array[String] = []
	for relation in sim.relations.relations_of(speaker.id):
		var other: Agent = sim.agent_by_id(relation["other"])
		if other == null:
			continue
		var kind: int = relation["kind"]
		parts.append("%s (%s)" % [other.display_name, _describe_tie(kind)])
	return ", ".join(parts)


static func _describe_tie(kind: int) -> String:
	const K := RelationGraph.Kind
	match kind:
		K.KIN: return "your blood"
		K.MARRIAGE: return "your spouse"
		K.AFFAIR: return "your lover, in secret"
		K.UNREQUITED: return "you love them and have never said so"
		K.DEBT: return "you owe them, and resent it"
		K.LIFE_DEBT: return "they saved your life"
		K.MENTOR: return "you look up to them"
		K.FRIENDSHIP: return "an old friend"
		K.ESTRANGED: return "you were close once, and are not now"
		K.RIVALRY: return "you despise them"
		_: return "known to you"


static func _describe_secrets(speaker: Agent, sim: TownSim) -> String:
	if sim == null:
		return ""
	var parts: Array[String] = []
	for secret in sim.secrets_about(speaker.id):
		parts.append(_describe_secret(secret, speaker.id, sim))
	return " ".join(parts)


static func _describe_secret(secret: Secret, holder_id: StringName, sim: TownSim) -> String:
	var token: MemoryToken = secret.content
	var target_name: String = str(token.target_id)
	var target: Agent = sim.agent_by_id(token.target_id)
	if target != null:
		target_name = target.display_name

	var verb: String = str(token.action).replace("_", " ")
	var subject: Agent = sim.agent_by_id(token.subject_id)
	var subject_name: String = subject.display_name if subject != null else str(token.subject_id)

	if token.subject_id == holder_id:
		return "You %s %s." % [verb, target_name]
	if token.target_id == holder_id:
		return "%s %s you." % [subject_name, verb]

	# A participant who is neither party — the Blacksmith lied to the Sheriff to
	# protect the Widow, so she is ruined by it without appearing in the claim.
	return "%s %s %s, and you would be ruined if it came out." % [subject_name, verb, target_name]


static func _describe_beliefs(speaker: Agent) -> String:
	var parts: Array[String] = []
	for token in speaker.ledger.about(Agent.PLAYER_ID).slice(0, MEMORY_BUDGET):
		var verb: String = str(token.action).replace("_", " ")
		var suffix: String = "" if token.truth_value else " (though you are not sure it is true)"
		parts.append("they %s %s%s" % [verb, token.target_id, suffix])
	return "; ".join(parts)


static func _describe_regard(score: float) -> String:
	if score > 80.0:
		return "you trust them and would back them"
	if score > 62.0:
		return "you are warming to them"
	if score > 45.0:
		return "you are wary but civil"
	if score > 25.0:
		return "you distrust them"
	return "you despise them"
