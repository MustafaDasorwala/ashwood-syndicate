class_name Archetypes
extends RefCounted

## The stock of people a town can be built from.
##
## Each entry is a coherent human being rather than a bundle of sliders: the
## traits, the morals and the job all point the same way, so the generator can
## pick ten of these and get a town that reads as written rather than rolled.
##
## Personality is varied per playthrough on top of these, but the *shape* is
## fixed here. Rolling OCEAN values freely produces ten incoherent people and no
## amount of relationship weaving rescues that.

const _T := Psyche.Trait
const _D := Psyche.Dark
const _F := Psyche.Foundation
const _Z := TownGrid.Zone

## How far a generated personality may drift from its archetype, per axis.
const VARIATION := 0.15

## Every archetype. `ambition` decides who runs for the leadership; `wealth`
## decides who other people end up owing.
const ALL := [
	{
		"key": &"lawman", "role": "Sheriff", "title_first": true,
		"traits": {_T.CONSCIENTIOUSNESS: 0.9, _T.AGREEABLENESS: 0.3, _T.NEUROTICISM: 0.3},
		"dark": {_D.MACHIAVELLIANISM: 0.3},
		"morality": {_F.AUTHORITY: 0.95, _F.FAIRNESS: 0.7, _F.CARE: 0.35},
		"zone": _Z.SHERIFF, "need": Agent.Need.RESPECT,
		"ambition": 0.5, "wealth": 0.3, "protector": true,
	},
	{
		"key": &"elder", "role": "Mayor", "title_first": true,
		"traits": {_T.CONSCIENTIOUSNESS: 0.8, _T.EXTRAVERSION: 0.8, _T.OPENNESS: 0.3},
		"dark": {_D.NARCISSISM: 0.6, _D.MACHIAVELLIANISM: 0.4},
		"morality": {_F.FAIRNESS: 0.8, _F.AUTHORITY: 0.8, _F.LOYALTY: 0.6},
		"zone": _Z.MARKET, "need": Agent.Need.RESPECT,
		"ambition": 0.95, "wealth": 0.6, "bias": Psyche.Bias.SUNK_COST,
	},
	{
		"key": &"merchant", "role": "the Merchant", "title_first": false,
		"traits": {_T.EXTRAVERSION: 0.9, _T.AGREEABLENESS: 0.2, _T.OPENNESS: 0.7},
		"dark": {_D.MACHIAVELLIANISM: 0.9, _D.NARCISSISM: 0.6, _D.PSYCHOPATHY: 0.4},
		"morality": {_F.FAIRNESS: 0.12, _F.CARE: 0.2, _F.AUTHORITY: 0.15, _F.SANCTITY: 0.1},
		"zone": _Z.MARKET, "need": Agent.Need.MONEY,
		"ambition": 0.9, "wealth": 1.0,
	},
	{
		"key": &"smith", "role": "the Smith", "title_first": false,
		"traits": {_T.CONSCIENTIOUSNESS: 0.7, _T.AGREEABLENESS: 0.6, _T.NEUROTICISM: 0.2},
		"dark": {},
		"morality": {_F.LOYALTY: 0.85, _F.CARE: 0.7, _F.FAIRNESS: 0.6},
		"zone": _Z.MARKET, "need": Agent.Need.MONEY,
		"ambition": 0.2, "wealth": 0.4,
	},
	{
		"key": &"miller", "role": "the Miller", "title_first": false,
		"traits": {_T.CONSCIENTIOUSNESS: 0.85, _T.OPENNESS: 0.2, _T.NEUROTICISM: 0.4},
		"dark": {},
		"morality": {_F.AUTHORITY: 0.9, _F.SANCTITY: 0.6, _F.CARE: 0.3},
		"zone": _Z.MARKET, "need": Agent.Need.SAFETY,
		"ambition": 0.1, "wealth": 0.2, "bias": Psyche.Bias.CONFIRMATION,
		"trigger": ActionCatalog.FLATTERED,
	},
	{
		"key": &"healer", "role": "the Healer", "title_first": false,
		"traits": {_T.AGREEABLENESS: 0.9, _T.OPENNESS: 0.7, _T.CONSCIENTIOUSNESS: 0.7},
		"dark": {},
		"morality": {_F.CARE: 0.95, _F.FAIRNESS: 0.7, _F.AUTHORITY: 0.3},
		"zone": _Z.RESIDENCES, "need": Agent.Need.BELONGING,
		"ambition": 0.15, "wealth": 0.3, "protector": true, "caregiver": true,
	},
	{
		"key": &"preacher", "role": "Brother", "title_first": true,
		"traits": {_T.CONSCIENTIOUSNESS: 0.8, _T.OPENNESS: 0.2, _T.EXTRAVERSION: 0.6},
		"dark": {_D.NARCISSISM: 0.4},
		"morality": {_F.SANCTITY: 0.95, _F.AUTHORITY: 0.7, _F.CARE: 0.5},
		"zone": _Z.RESIDENCES, "need": Agent.Need.RESPECT,
		"ambition": 0.4, "wealth": 0.3,
	},
	{
		"key": &"drunkard", "role": "Old", "title_first": true,
		"traits": {_T.EXTRAVERSION: 0.95, _T.NEUROTICISM: 0.8, _T.CONSCIENTIOUSNESS: 0.1},
		"dark": {_D.PSYCHOPATHY: 0.2},
		"morality": {_F.LOYALTY: 0.4, _F.CARE: 0.5, _F.AUTHORITY: 0.2},
		"zone": _Z.TAVERN, "need": Agent.Need.BELONGING,
		"ambition": 0.05, "wealth": 0.1,
	},
	{
		"key": &"widow", "role": "Widow", "title_first": true,
		"traits": {_T.NEUROTICISM: 0.7, _T.EXTRAVERSION: 0.2, _T.OPENNESS: 0.4},
		"dark": {_D.MACHIAVELLIANISM: 0.3},
		"morality": {_F.LOYALTY: 0.8, _F.CARE: 0.7, _F.SANCTITY: 0.6},
		"zone": _Z.RESIDENCES, "need": Agent.Need.SAFETY,
		"ambition": 0.1, "wealth": 0.2, "bias": Psyche.Bias.CONFIRMATION,
	},
	{
		"key": &"trapper", "role": "the Trapper", "title_first": false,
		"traits": {_T.OPENNESS: 0.6, _T.EXTRAVERSION: 0.1, _T.AGREEABLENESS: 0.3},
		"dark": {_D.PSYCHOPATHY: 0.5, _D.MACHIAVELLIANISM: 0.5},
		"morality": {_F.FAIRNESS: 0.6, _F.CARE: 0.3, _F.AUTHORITY: 0.2},
		"zone": _Z.WOODS, "need": Agent.Need.SAFETY,
		"ambition": 0.1, "wealth": 0.3, "loner": true,
	},
	{
		"key": &"innkeeper", "role": "the Innkeeper", "title_first": false,
		"traits": {_T.EXTRAVERSION: 0.85, _T.AGREEABLENESS: 0.7, _T.CONSCIENTIOUSNESS: 0.6},
		"dark": {_D.MACHIAVELLIANISM: 0.4},
		"morality": {_F.LOYALTY: 0.7, _F.FAIRNESS: 0.5, _F.CARE: 0.6},
		"zone": _Z.TAVERN, "need": Agent.Need.MONEY,
		"ambition": 0.35, "wealth": 0.7,
	},
	{
		"key": &"gravedigger", "role": "the Gravedigger", "title_first": false,
		"traits": {_T.EXTRAVERSION: 0.15, _T.OPENNESS: 0.5, _T.NEUROTICISM: 0.5},
		"dark": {_D.PSYCHOPATHY: 0.4},
		"morality": {_F.SANCTITY: 0.7, _F.CARE: 0.4, _F.AUTHORITY: 0.4},
		"zone": _Z.WOODS, "need": Agent.Need.BELONGING,
		"ambition": 0.05, "wealth": 0.15, "loner": true,
	},
	{
		"key": &"teacher", "role": "the Schoolmistress", "title_first": false,
		"traits": {_T.OPENNESS: 0.85, _T.CONSCIENTIOUSNESS: 0.75, _T.AGREEABLENESS: 0.6},
		"dark": {},
		"morality": {_F.FAIRNESS: 0.85, _F.CARE: 0.7, _F.AUTHORITY: 0.5},
		"zone": _Z.RESIDENCES, "need": Agent.Need.RESPECT,
		"ambition": 0.45, "wealth": 0.25, "protector": true,
	},
	{
		"key": &"gambler", "role": "the Gambler", "title_first": false,
		"traits": {_T.EXTRAVERSION: 0.8, _T.CONSCIENTIOUSNESS: 0.2, _T.OPENNESS: 0.7},
		"dark": {_D.MACHIAVELLIANISM: 0.7, _D.NARCISSISM: 0.5},
		"morality": {_F.FAIRNESS: 0.25, _F.LOYALTY: 0.3, _F.AUTHORITY: 0.2},
		"zone": _Z.TAVERN, "need": Agent.Need.MONEY,
		"ambition": 0.3, "wealth": 0.35,
	},
	{
		"key": &"midwife", "role": "the Midwife", "title_first": false,
		"traits": {_T.AGREEABLENESS: 0.8, _T.EXTRAVERSION: 0.5, _T.NEUROTICISM: 0.35},
		"dark": {},
		"morality": {_F.CARE: 0.9, _F.SANCTITY: 0.55, _F.LOYALTY: 0.6},
		"zone": _Z.RESIDENCES, "need": Agent.Need.BELONGING,
		"ambition": 0.15, "wealth": 0.25, "protector": true, "caregiver": true,
	},
	{
		"key": &"farrier", "role": "the Farrier", "title_first": false,
		"traits": {_T.CONSCIENTIOUSNESS: 0.65, _T.AGREEABLENESS: 0.45, _T.EXTRAVERSION: 0.4},
		"dark": {_D.NARCISSISM: 0.3},
		"morality": {_F.LOYALTY: 0.65, _F.AUTHORITY: 0.55, _F.FAIRNESS: 0.55},
		"zone": _Z.MARKET, "need": Agent.Need.MONEY,
		"ambition": 0.25, "wealth": 0.45,
	},
]

## Archetypes that must appear in every town, because whole mechanics depend on
## them: somebody has to be the law a frightened NPC runs to, and somebody has
## to be rich enough to be owed.
const REQUIRED := [&"lawman", &"merchant"]


static func by_key(key: StringName) -> Dictionary:
	for entry in ALL:
		if entry["key"] == key:
			return entry
	return {}


## Builds a psyche from an archetype, jittered so two towns with the same cast
## still contain different people.
static func make_psyche(entry: Dictionary, id: StringName, display_name: String, rng: SimRng) -> Psyche:
	var psyche := Psyche.new(id, display_name, entry["traits"], entry["dark"], entry["morality"])

	for t in Psyche.Trait.values():
		psyche.traits[t] = clampf(psyche.traits[t] + _jitter(rng), 0.0, 1.0)
	for d in Psyche.Dark.values():
		psyche.dark_triad[d] = clampf(psyche.dark_triad[d] + _jitter(rng), 0.0, 1.0)
	for f in Psyche.Foundation.values():
		psyche.morality[f] = clampf(psyche.morality[f] + _jitter(rng), 0.0, 1.0)

	psyche.bias = entry.get("bias", Psyche.Bias.NONE)
	psyche.trauma_trigger = entry.get("trigger", &"")
	return psyche


static func _jitter(rng: SimRng) -> float:
	return (rng.randf() * 2.0 - 1.0) * VARIATION
