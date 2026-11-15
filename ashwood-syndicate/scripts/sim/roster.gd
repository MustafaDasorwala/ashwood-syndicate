class_name Roster
extends RefCounted

## Builds the ten inhabitants of Ashwood.
##
## Each is a hand-authored psychological profile rather than a random roll, so
## the town has deliberate fault lines: a Fairness zealot who cannot abide a
## bribe, a manipulator who profits from one, a pair of rivals whose feud drags
## in everyone around them.
##
## Profiles here are the same shape the LLM persona prompts consume, so Phase 2
## can serialise an Agent straight into a system prompt.

const _T := Psyche.Trait
const _D := Psyche.Dark
const _F := Psyche.Foundation
const _Z := TownGrid.Zone

const SHERIFF := &"sheriff"
const MAYOR := &"mayor"
const BLACKSMITH := &"blacksmith"
const MERCHANT := &"merchant"
const MILLER := &"miller"
const HEALER := &"healer"
const PREACHER := &"preacher"
const DRUNKARD := &"drunkard"
const WIDOW := &"widow"
const TRAPPER := &"trapper"


## The ten NPCs, in a stable order.
static func build_all() -> Array[Agent]:
	return [
		_sheriff(),
		_mayor(),
		_blacksmith(),
		_merchant(),
		_miller(),
		_healer(),
		_preacher(),
		_drunkard(),
		_widow(),
		_trapper(),
	]


## The ties that bind Ashwood together.
##
## Sparse on purpose: roughly fifteen edges across ten people, clustered rather
## than spread evenly, with Cass deliberately near-isolated. A fully connected
## town has no shape and nothing for the player to discover.
##
## The centrepiece is a triangle nobody has all three sides of. Bram loves the
## Widow and does not know she is involved with the Preacher; the Preacher does
## not know Bram is a threat. Telling the wrong person is a whole strategy.
static func build_relations() -> RelationGraph:
	const K := RelationGraph.Kind
	var graph := RelationGraph.new()

	# The triangle.
	graph.add(PREACHER, WIDOW, K.AFFAIR)
	graph.add(BLACKSMITH, WIDOW, K.UNREQUITED)

	# Family. Maret and Elias are siblings, which puts the healer's conscience
	# directly against the Merchant's hold over her brother.
	graph.add(HEALER, MILLER, K.KIN)

	# Money. Both of these run one way, toward the man holding the paper.
	graph.add(SHERIFF, MERCHANT, K.DEBT)
	graph.add(MILLER, MERCHANT, K.DEBT)

	# Cass owes Maret his life and almost nothing else to anyone.
	graph.add(TRAPPER, HEALER, K.LIFE_DEBT)

	# Warmth.
	graph.add(BLACKSMITH, DRUNKARD, K.FRIENDSHIP)
	graph.add(MAYOR, SHERIFF, K.FRIENDSHIP)

	# The Merchant needs somebody in his corner. Without one he opened the week
	# owed-by and feuding and nothing else, and lost every measured playthrough
	# to the Mayor 9-1 — a three-way race with one inert candidate is a two-way
	# race with extra steps. An alliance of the disreputable fits them both.
	graph.add(MERCHANT, DRUNKARD, K.FRIENDSHIP)

	# Deference.
	graph.add(PREACHER, MAYOR, K.MENTOR)

	# Old wounds.
	graph.add(DRUNKARD, MILLER, K.ESTRANGED)

	# Feuds. These were the whole of the old model.
	graph.add(SHERIFF, DRUNKARD, K.RIVALRY)
	graph.add(PREACHER, DRUNKARD, K.RIVALRY)
	graph.add(MAYOR, MERCHANT, K.RIVALRY)

	return graph


## What the town does not know, and who each disclosure would ruin.
##
## Several are shared, which is the point: the affair is one secret held by two
## people, and the Sheriff's arrangement destroys the Merchant alongside him.
## Because the Merchant is a candidate, that one is worth the whole election.
static func build_secrets() -> Array[Secret]:
	var out: Array[Secret] = []

	# Shared. Ruinous to both.
	out.append(_secret(&"the_affair", PREACHER, ActionCatalog.ROMANCED, WIDOW, 7,
		[PREACHER, WIDOW] as Array[StringName], 0.9))
	# The Merchant pays; the Sheriff takes. Written subject-first because that is
	# how it reads back out in dialogue: "Yolen the Merchant bribed you."
	out.append(_secret(&"the_payroll", MERCHANT, ActionCatalog.BRIBED, SHERIFF, 8,
		[SHERIFF, MERCHANT] as Array[StringName], 0.95))
	out.append(_secret(&"the_squeeze", MERCHANT, ActionCatalog.BLACKMAILED, MILLER, 8,
		[MERCHANT, MILLER] as Array[StringName], 0.8))
	out.append(_secret(&"the_false_alibi", BLACKSMITH, ActionCatalog.LIED_TO, SHERIFF, 5,
		[BLACKSMITH, WIDOW] as Array[StringName], 0.5))

	# Carried alone.
	out.append(_secret(&"the_ledger", MAYOR, ActionCatalog.STOLE_FROM, &"the town purse", 9,
		[MAYOR] as Array[StringName], 0.9))
	out.append(_secret(&"the_mercy", HEALER, ActionCatalog.KILLED, &"a dying patient", 9,
		[HEALER] as Array[StringName], 0.85))
	out.append(_secret(&"the_informer", DRUNKARD, ActionCatalog.BETRAYED, BLACKSMITH, 6,
		[DRUNKARD] as Array[StringName], 0.6))
	out.append(_secret(&"the_woods", TRAPPER, ActionCatalog.KILLED, &"a stranger in the woods", 10,
		[TRAPPER] as Array[StringName], 1.0))

	return out


static func _secret(
	id: StringName,
	subject: StringName,
	action: StringName,
	target: StringName,
	severity: int,
	participants: Array[StringName],
	weight: float
) -> Secret:
	return Secret.new(
		id, MemoryToken.new(subject, action, target, true, severity, &"", 0), participants, weight
	)


static func _make(
	id: StringName,
	display_name: String,
	traits: Dictionary,
	dark: Dictionary,
	morality: Dictionary,
	work_zone: int
) -> Agent:
	var psyche := Psyche.new(id, display_name, traits, dark, morality)
	return Agent.new(psyche, Schedule.for_workplace(work_zone))


## Rigid enforcer. Authority above compassion, so a lawful cruelty troubles him
## less than an unlawful kindness.
static func _sheriff() -> Agent:
	var agent := _make(
		SHERIFF, "Sheriff Calder",
		{_T.CONSCIENTIOUSNESS: 0.9, _T.AGREEABLENESS: 0.3, _T.NEUROTICISM: 0.3, _T.EXTRAVERSION: 0.4},
		{_D.MACHIAVELLIANISM: 0.3},
		{_F.AUTHORITY: 0.95, _F.FAIRNESS: 0.7, _F.CARE: 0.35, _F.LOYALTY: 0.6, _F.SANCTITY: 0.4},
		_Z.SHERIFF
	)
	agent.psyche.rivals = [DRUNKARD]
	agent.set_need(Agent.Need.RESPECT, 0.4)
	return agent


## Invested in the old order and unable to admit it is failing.
static func _mayor() -> Agent:
	var agent := _make(
		MAYOR, "Mayor Thorne",
		{_T.CONSCIENTIOUSNESS: 0.8, _T.EXTRAVERSION: 0.8, _T.AGREEABLENESS: 0.5, _T.OPENNESS: 0.3},
		{_D.NARCISSISM: 0.6, _D.MACHIAVELLIANISM: 0.4},
		{_F.FAIRNESS: 0.8, _F.AUTHORITY: 0.8, _F.LOYALTY: 0.6, _F.CARE: 0.5, _F.SANCTITY: 0.3},
		_Z.MARKET
	)
	agent.psyche.bias = Psyche.Bias.SUNK_COST
	agent.psyche.rivals = [MERCHANT]
	agent.set_need(Agent.Need.RESPECT, 0.6)
	return agent


## Straightforward, physically confident, fiercely attached to his sister.
static func _blacksmith() -> Agent:
	var agent := _make(
		BLACKSMITH, "Bram the Smith",
		{_T.CONSCIENTIOUSNESS: 0.7, _T.AGREEABLENESS: 0.6, _T.NEUROTICISM: 0.2, _T.EXTRAVERSION: 0.5},
		{},
		{_F.LOYALTY: 0.85, _F.CARE: 0.7, _F.FAIRNESS: 0.6, _F.AUTHORITY: 0.4, _F.SANCTITY: 0.3},
		_Z.MARKET
	)
	agent.psyche.loyal_to = [WIDOW]
	agent.set_need(Agent.Need.MONEY, 0.5)
	return agent


## Reads every transaction as leverage. Respects anyone willing to play dirty.
static func _merchant() -> Agent:
	var agent := _make(
		MERCHANT, "Yolen the Merchant",
		{_T.EXTRAVERSION: 0.9, _T.AGREEABLENESS: 0.2, _T.OPENNESS: 0.7, _T.CONSCIENTIOUSNESS: 0.6},
		{_D.MACHIAVELLIANISM: 0.9, _D.NARCISSISM: 0.6, _D.PSYCHOPATHY: 0.4},
		# Fairness and Authority sit low enough that a bribe reads as competence
		# rather than crime — the design doc's Corrupt Merchant, who *gains*
		# respect for the player when they play dirty.
		{_F.FAIRNESS: 0.12, _F.CARE: 0.2, _F.LOYALTY: 0.3, _F.AUTHORITY: 0.15, _F.SANCTITY: 0.1},
		_Z.MARKET
	)
	agent.psyche.rivals = [MAYOR]
	agent.set_need(Agent.Need.MONEY, 0.7)
	return agent


## Elias from the design doc: rule-following, in debt, and undone by flattery.
static func _miller() -> Agent:
	var agent := _make(
		MILLER, "Elias the Miller",
		{_T.CONSCIENTIOUSNESS: 0.85, _T.OPENNESS: 0.2, _T.NEUROTICISM: 0.4, _T.AGREEABLENESS: 0.5},
		{},
		{_F.AUTHORITY: 0.9, _F.SANCTITY: 0.6, _F.FAIRNESS: 0.6, _F.CARE: 0.3, _F.LOYALTY: 0.5},
		_Z.MARKET
	)
	agent.psyche.bias = Psyche.Bias.CONFIRMATION
	# Betrayed by a smooth-talking merchant in his youth: flattery, not
	# betrayal itself, is what trips the wire. Straight from the design doc.
	agent.psyche.trauma_trigger = ActionCatalog.FLATTERED
	agent.set_need(Agent.Need.SAFETY, 0.6)
	return agent


## Sees the whole town's private harm and weighs Care above all.
static func _healer() -> Agent:
	var agent := _make(
		HEALER, "Maret the Healer",
		{_T.AGREEABLENESS: 0.9, _T.OPENNESS: 0.7, _T.CONSCIENTIOUSNESS: 0.7, _T.NEUROTICISM: 0.4},
		{},
		{_F.CARE: 0.95, _F.FAIRNESS: 0.7, _F.SANCTITY: 0.5, _F.LOYALTY: 0.4, _F.AUTHORITY: 0.3},
		_Z.RESIDENCES
	)
	agent.set_need(Agent.Need.BELONGING, 0.3)
	return agent


## Purity above mercy. Will not be seen alongside the disreputable.
static func _preacher() -> Agent:
	var agent := _make(
		PREACHER, "Brother Adric",
		{_T.CONSCIENTIOUSNESS: 0.8, _T.OPENNESS: 0.2, _T.EXTRAVERSION: 0.6, _T.AGREEABLENESS: 0.4},
		{_D.NARCISSISM: 0.4},
		{_F.SANCTITY: 0.95, _F.AUTHORITY: 0.7, _F.CARE: 0.5, _F.LOYALTY: 0.5, _F.FAIRNESS: 0.5},
		_Z.RESIDENCES
	)
	agent.psyche.rivals = [DRUNKARD]
	agent.set_need(Agent.Need.RESPECT, 0.5)
	return agent


## Loud, anxious, permanently in the tavern, and therefore the town's
## fastest-moving carrier of rumour.
static func _drunkard() -> Agent:
	var agent := _make(
		DRUNKARD, "Old Pell",
		{_T.EXTRAVERSION: 0.95, _T.NEUROTICISM: 0.8, _T.CONSCIENTIOUSNESS: 0.1, _T.AGREEABLENESS: 0.6},
		{_D.PSYCHOPATHY: 0.2},
		{_F.LOYALTY: 0.4, _F.CARE: 0.5, _F.FAIRNESS: 0.4, _F.AUTHORITY: 0.2, _F.SANCTITY: 0.1},
		_Z.TAVERN
	)
	agent.set_need(Agent.Need.BELONGING, 0.7)
	return agent


## Grieving, guarded, and the emotional lever on the blacksmith.
static func _widow() -> Agent:
	var agent := _make(
		WIDOW, "Widow Serrin",
		{_T.NEUROTICISM: 0.7, _T.AGREEABLENESS: 0.5, _T.EXTRAVERSION: 0.2, _T.OPENNESS: 0.4},
		{_D.MACHIAVELLIANISM: 0.3},
		{_F.LOYALTY: 0.8, _F.CARE: 0.7, _F.SANCTITY: 0.6, _F.FAIRNESS: 0.5, _F.AUTHORITY: 0.4},
		_Z.RESIDENCES
	)
	agent.psyche.loyal_to = [BLACKSMITH]
	agent.psyche.bias = Psyche.Bias.CONFIRMATION
	agent.set_need(Agent.Need.SAFETY, 0.5)
	return agent


## Works the woods alone. Trusts nobody, owes nobody, and sees a great deal.
static func _trapper() -> Agent:
	var agent := _make(
		TRAPPER, "Cass the Trapper",
		{_T.OPENNESS: 0.6, _T.EXTRAVERSION: 0.1, _T.AGREEABLENESS: 0.3, _T.NEUROTICISM: 0.5},
		{_D.PSYCHOPATHY: 0.5, _D.MACHIAVELLIANISM: 0.5},
		{_F.FAIRNESS: 0.6, _F.CARE: 0.3, _F.AUTHORITY: 0.2, _F.LOYALTY: 0.3, _F.SANCTITY: 0.2},
		_Z.WOODS
	)
	agent.set_need(Agent.Need.SAFETY, 0.4)
	return agent
