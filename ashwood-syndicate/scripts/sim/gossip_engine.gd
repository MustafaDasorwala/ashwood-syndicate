class_name GossipEngine
extends RefCounted

## The background social simulation. No text is generated here.
##
## Running an LLM for every NPC-to-NPC interaction would saturate the local
## server within seconds, so all off-screen conversation is resolved as
## arithmetic over Memory Tokens. The LLM is reserved for scenes the player is
## actually in — and when that happens, the tokens produced here are injected
## into the prompt, so the dialogue references gossip the player never saw.
##
## Three operations make up an exchange:
##   1. `select_token`  - what would this speaker choose to bring up?
##   2. `distort`       - do they twist it on the way out?
##   3. `evaluate`      - what does hearing it do to the listener's opinion?

## Largest relationship swing a single maximally-offensive claim can cause.
## Bounded so no one token can decide the election on its own.
const MAX_SWING := 22.0

## Weight of Dark Triad admiration for ruthless behaviour, as a fraction of
## MAX_SWING. A manipulator respects a rival who plays dirty.
##
## Tuned so a thoroughly amoral personality (low Fairness, high Machiavellianism)
## reads a bribe as competence rather than as a crime — the Corrupt Merchant
## archetype from the design docs — while an ordinary NPC still condemns it.
const ADMIRATION_WEIGHT := 0.65

## Weight of vanity appeal, as a fraction of MAX_SWING. Flattery is cheap, so it
## pays less than a genuine favour even against a maximally vain target.
const VANITY_WEIGHT := 0.8

## Per in-game hour, the chance two idle NPCs sharing a zone converse.
const PASSIVE_CHANCE := 0.30

## Chance a sufficiently dark personality alters a claim before passing it on.
const DISTORTION_CHANCE := 0.35

## Dark factor below which an NPC never knowingly distorts information.
const DISTORTION_FLOOR := 0.45

## Multiplier applied when a claim lands on the listener's core trauma.
const TRAUMA_AMPLIFIER := 2.0

## How strongly confirmation bias amplifies agreeable evidence and suppresses
## inconvenient evidence.
const BIAS_STRENGTH := 0.5

## Regard below which the listener treats a kindness toward that person as
## taking sides against them.
const DISLIKE_THRESHOLD := 35.0

## How much of a favour's value is turned against you for siding with someone
## the listener despises.
const SIDING_PENALTY := 0.8


## How much `listener`'s opinion of the token's subject should move on first
## learning this claim. Negative means the subject looks worse.
##
## The whole psychology stack feeds in here — this function is why the design
## documents matter mechanically rather than decoratively.
static func evaluate(token: MemoryToken, listener: Agent) -> float:
	var psyche: Psyche = listener.psyche

	# An NPC's opinion of themselves does not move on hearsay about themselves.
	if token.subject_id == listener.id:
		return 0.0

	var severity: float = float(token.severity) / 10.0

	# 1. Moral offense, weighted by what THIS listener holds sacred. The same
	#    bribe outrages a Fairness zealot and barely registers on a cynic.
	#
	#    The raw sum is saturated rather than clamped. A hard clamp would flatten
	#    every multi-foundation violation to the same ceiling, which made murder
	#    and theft score identically for anyone with broadly strong morals — and
	#    then murder came out *ahead* on the ruthlessness bonus below.
	var raw_offense: float = 0.0
	for foundation in ActionCatalog.violated_foundations(token.action):
		raw_offense += ActionCatalog.violation(token.action, foundation) * psyche.moral_of(foundation)
	var offense: float = raw_offense / (1.0 + raw_offense)

	var delta: float = -offense * severity * MAX_SWING

	# 2. Prosocial acts read positively, scaled by how much the listener values
	#    Care in the first place.
	if ActionCatalog.is_prosocial(token.action):
		delta += severity * MAX_SWING * (0.4 + 0.6 * psyche.moral_of(Psyche.Foundation.CARE))

	# 3. Dark Triad admiration. Ruthlessness impresses the ruthless, partially
	#    offsetting the moral penalty rather than replacing it.
	var admiration: float = (
		ActionCatalog.ruthlessness(token.action)
		* psyche.dark_factor()
		* severity
		* MAX_SWING
		* ADMIRATION_WEIGHT
	)
	delta += admiration

	# 3b. Vanity. Flattery works on self-regard rather than morals, so it wins
	#     over a narcissist and slides off someone with no need to be admired.
	delta += (
		ActionCatalog.vanity(token.action)
		* psyche.dark_of(Psyche.Dark.NARCISSISM)
		* severity
		* MAX_SWING
		* VANITY_WEIGHT
	)

	# 4. Attachments override personality. Harm to someone they love hits far
	#    harder; wrongdoing by someone they love is quietly excused.
	#
	#    Scaled by the strength of the actual tie, so harming a man's brother,
	#    his business partner and his secret lover are three different events
	#    rather than one generic "someone he likes".
	var tie_to_target: float = listener.attachment_to(token.target_id)
	if token.target_id != &"" and tie_to_target > 0.0:
		delta *= (1.0 + tie_to_target) if delta < 0.0 else (1.0 + 0.25 * tie_to_target)

	var tie_to_subject: float = listener.attachment_to(token.subject_id)
	if delta < 0.0 and tie_to_subject > 0.0:
		delta *= 1.0 - 0.75 * tie_to_subject
	elif delta < 0.0 and tie_to_subject < 0.0:
		delta *= 1.0 + 0.625 * absf(tie_to_subject)

	# 4b. Favours are not universal currency. Doing a kindness for someone the
	#     listener cannot stand reads as picking the wrong side, which is what
	#     stops "be generous to everybody" from being a dominant strategy with
	#     no cost attached.
	if delta > 0.0 and token.target_id != &"" and token.target_id != listener.id:
		var regard_for_target: float = listener.relationships.score_for(token.target_id)
		if regard_for_target < DISLIKE_THRESHOLD or tie_to_target < 0.0:
			delta *= -SIDING_PENALTY

	# 5. Trauma bypasses evaluation entirely and resolves as raw hostility.
	#
	#    Note this is a floor, not a multiplier. Scaling the computed delta alone
	#    would mean an NPC whose morals happen not to condemn the act barely
	#    reacts to their own ghost — but the whole point of a trigger is that it
	#    fires regardless of what they otherwise believe.
	if psyche.is_triggered_by(token.action):
		var trauma_floor: float = -MAX_SWING * (0.35 + 0.65 * severity)
		delta = minf(-absf(delta) * TRAUMA_AMPLIFIER, trauma_floor)

	# 6. Cognitive bias distorts how readily the evidence is accepted.
	delta = _apply_bias(delta, token, listener)

	# 7. Agreeable people are slower to condemn.
	if delta < 0.0:
		delta *= 1.0 - 0.3 * psyche.trait_of(Psyche.Trait.AGREEABLENESS)

	# 8. Falsehoods still land — the listener cannot tell — but rumours carry
	#    slightly less weight than lived fact, leaving room for a later
	#    correction to matter.
	if not token.truth_value:
		delta *= 0.85

	# 9. Finally, discount by how much the listener trusts whoever told them.
	#    A rival's word is nearly worthless; firsthand sight is undiscounted.
	delta *= listener.relationships.trust_in(token.origin_id)

	return clampf(delta, -MAX_SWING, MAX_SWING)


## Confirmation bias, sunk cost and the halo effect, applied to a raw delta.
static func _apply_bias(delta: float, token: MemoryToken, listener: Agent) -> float:
	match listener.psyche.bias:
		Psyche.Bias.CONFIRMATION:
			# Already dislike them? Bad news is obviously true. Good news is not.
			var lean: float = listener.relationships.score_for(token.subject_id) - RelationshipBook.NEUTRAL
			var agrees: bool = (lean < 0.0 and delta < 0.0) or (lean > 0.0 and delta > 0.0)
			var strength: float = BIAS_STRENGTH * absf(lean) / RelationshipBook.NEUTRAL
			return delta * (1.0 + strength) if agrees else delta * (1.0 - strength)

		Psyche.Bias.SUNK_COST:
			# Having already committed to someone, they resist evidence against
			# them regardless of how damning it is.
			if delta < 0.0 and listener.relationships.score_for(token.subject_id) > RelationshipBook.NEUTRAL:
				return delta * (1.0 - BIAS_STRENGTH)
			return delta

		Psyche.Bias.HALO:
			# Charm suppresses red flags about anyone already well liked.
			if delta < 0.0 and listener.relationships.would_vote_for(token.subject_id):
				return delta * (1.0 - BIAS_STRENGTH)
			return delta

		_:
			return delta


## What `speaker` chooses to bring up with `listener`, or null when they have
## nothing worth saying.
##
## Selection is trait-driven, per the design doc: gossips reach for whatever is
## most scandalous, manipulators for whatever damages a rival, and the anxious
## for whatever feels like a threat.
static func select_token(speaker: Agent, listener: Agent, rng: SimRng) -> MemoryToken:
	var candidates: Array[MemoryToken] = []
	var weights: Array[float] = []

	for token in speaker.ledger.all():
		# No point retelling what they already believe, and nobody badmouths
		# their listener to their face.
		if listener.ledger.knows(token) or token.subject_id == listener.id:
			continue

		candidates.append(token)
		weights.append(_share_weight(token, speaker))

	if candidates.is_empty():
		return null
	return rng.pick_weighted(candidates, weights)


## How motivated `speaker` is to repeat this particular claim.
static func _share_weight(token: MemoryToken, speaker: Agent) -> float:
	var psyche: Psyche = speaker.psyche
	var severity: float = float(token.severity) / 10.0

	# Baseline keeps every belief technically shareable, so a low-trait speaker
	# still says something rather than standing mute.
	var weight: float = 0.2

	# Extraverts trade in scandal.
	weight += psyche.trait_of(Psyche.Trait.EXTRAVERSION) * severity * 1.5

	# Manipulators push whatever damages someone they oppose.
	if token.subject_id in psyche.rivals:
		weight += psyche.dark_of(Psyche.Dark.MACHIAVELLIANISM) * 2.0

	# The anxious fixate on danger.
	var danger: float = ActionCatalog.violation(token.action, Psyche.Foundation.CARE)
	weight += psyche.trait_of(Psyche.Trait.NEUROTICISM) * danger * severity * 1.5

	# The loyal shield their own.
	if token.subject_id in psyche.loyal_to and not ActionCatalog.is_prosocial(token.action):
		weight *= 0.2

	return maxf(weight, 0.01)


## The version of `token` that actually leaves `speaker`'s mouth.
##
## Manipulative personalities rewrite information in transit: flipping a true
## account into a denial, or pinning someone else's deed on a rival. This is
## what makes late-game rumours untrustworthy even when their chain of custody
## looks clean.
static func distort(token: MemoryToken, speaker: Agent, day: int, rng: SimRng) -> MemoryToken:
	var retold: MemoryToken = token.retold_by(speaker.id, day)

	if speaker.psyche.dark_factor() < DISTORTION_FLOOR:
		return retold
	if not rng.chance(DISTORTION_CHANCE):
		return retold

	# Reframing onto a rival is the more useful lie when one is available.
	if not speaker.psyche.rivals.is_empty() and rng.chance(0.5):
		var scapegoat: Variant = rng.pick(speaker.psyche.rivals)
		if scapegoat != null and scapegoat != token.subject_id:
			retold.subject_id = scapegoat
			retold.truth_value = false
			return retold

	retold.truth_value = not retold.truth_value
	return retold


## Runs one conversation. Returns the token that changed hands, or null when
## nothing was said.
static func exchange(speaker: Agent, listener: Agent, day: int, rng: SimRng) -> MemoryToken:
	var chosen: MemoryToken = select_token(speaker, listener, rng)
	if chosen == null:
		return null

	var told: MemoryToken = distort(chosen, speaker, day, rng)
	listener.learn(told)
	EventBus.gossip_exchanged.emit(speaker.id, listener.id, told)
	return told


## Whether these two would strike up a conversation this hour.
##
## Extraverts start conversations more readily than the withdrawn, so the flat
## 30% from the design doc is modulated by both parties.
static func should_converse(a: Agent, b: Agent, rng: SimRng) -> bool:
	var sociability: float = 0.5 * (
		a.psyche.trait_of(Psyche.Trait.EXTRAVERSION)
		+ b.psyche.trait_of(Psyche.Trait.EXTRAVERSION)
	)
	var chance: float = PASSIVE_CHANCE * (0.5 + sociability)
	return rng.chance(clampf(chance, 0.0, 1.0))
