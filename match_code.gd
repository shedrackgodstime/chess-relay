class_name GameCode
extends RefCounted

## The short code a host gives someone so they can join.
##
## Alphabet with no 0, O, 1 or I in it. That is not fussiness: a code read aloud or
## typed from a message gets read wrongly, and a player entering 0 for O is sent to a
## game that does not exist and told the code was wrong, which is the least useful
## thing this screen can say. Removing the four confusable characters removes the
## mistake rather than explaining it afterwards.
##
## Six characters in two groups of three, so it can be read back over a voice call.

const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const GROUPS := 2
const LENGTH := 3


## A fresh code, from a seeded generator so a test can pin one.
static func generate(rng: RandomNumberGenerator = null) -> String:
	var source := rng if rng != null else RandomNumberGenerator.new()
	var parts: Array = []
	for g in GROUPS:
		var part := ""
		for i in LENGTH:
			part += ALPHABET[source.randi_range(0, ALPHABET.length() - 1)]
		parts.append(part)
	return "-".join(parts)


## Whether a typed code is the shape of a code, read forgivingly: spaces instead of a
## dash, any case, lower case in the message somebody pasted.
static func normalise(typed: String) -> String:
	var kept := ""
	for i in typed.length():
		var c := typed[i]
		if c == " " or c == "-":
			continue
		kept += c.to_upper()
	return kept


## Whether a code could be one of ours: the right letters, the right length.
##
## Normalises first, so a caller cannot get this wrong by handing it a displayed code
## with its dash still in it. It did exactly that, and refused a code it had just
## generated. Says nothing about whether a code exists, which nothing can know.
static func is_well_formed(code: String) -> bool:
	var clean := normalise(code)
	if clean.length() != GROUPS * LENGTH:
		return false
	for i in clean.length():
		if not ALPHABET.contains(clean[i]):
			return false
	return true
