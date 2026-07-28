class_name SaveIntegrity
extends RefCounted
## Tamper-evidence for the compliance / entitlement-critical save fields (M4-R2, ADR-0013 §4,
## ADR-0005). HMAC-SHA256 over a canonical string of the protected fields, keyed by a
## compiled-in app secret.
##
## [b]Threat model.[/b] The plain-JSON save (SaveService) lets anyone edit
## [member SaveData.age_band] or the consent / Remove-Ads flags to unlock targeted ads, IAP,
## or bypass child-safe mode. Signing makes such edits detectable: on load a bad or missing
## signature [b]fails closed[/b] — the caller resets the protected fields to their conservative
## defaults (UNKNOWN age, all consent denied, Remove-Ads not owned), re-triggering the age
## gate + consent flow.
##
## [b]Limitation (documented, not perfect anti-cheat).[/b] A client-side secret is inherently
## extractable from the binary; this raises save-editing well above plain-text tampering (the
## bar ADR-0013 §4 requires before a real Ad/Analytics SDK trusts these fields), but true
## integrity needs server-side authority. See M4-R2.
##
## Pure + deterministic (unit-tested); node-free; no resource loads.

## Dictionary key holding the signature in the serialized save.
const SIG_KEY: String = "_sig"

## The signed fields, in a fixed, load-bearing order (compliance ADR-0013 + entitlement
## ADR-0014). Changing the set or order invalidates every existing signature by design.
const PROTECTED_FIELDS: Array[String] = [
	"age_band",
	"consent_personalized_ads",
	"consent_analytics",
	"consent_iap",
	"consent_captured",
	"consent_version",
	"remove_ads_owned",
]

# Compiled-in app secret. NOTE: extractable from the client binary — raises the tamper bar,
# it is NOT server-grade anti-cheat (M4-R2 / ADR-0013 §4).
const _SECRET: String = "csm.v6.compliance.integrity.9f3c1a71"


## The canonical signing payload over the protected fields of [param dict], fixed order.
## Values are type-normalized so a JSON round-trip (which widens ints to floats) produces the
## identical string at sign-time and verify-time: booleans → 1/0, everything else → integer.
## Every protected field is bool- or integer-valued, so this is total and stable.
static func canonical(dict: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key in PROTECTED_FIELDS:
		var v: Variant = dict.get(key, null)
		var s: String
		if v == null:
			s = ""
		elif v is bool:
			s = "1" if v else "0"
		else:
			s = str(int(v))   # age_band / consent_version — stable whether int or float
		parts.append("%s=%s" % [key, s])
	return "|".join(parts)


## HMAC-SHA256 (hex) over the protected fields of [param dict].
static func signature(dict: Dictionary) -> String:
	var hmac := HMACContext.new()
	if hmac.start(HashingContext.HASH_SHA256, _SECRET.to_utf8_buffer()) != OK:
		return ""
	if hmac.update(canonical(dict).to_utf8_buffer()) != OK:
		return ""
	return hmac.finish().hex_encode()


## Returns a copy of [param dict] with [constant SIG_KEY] set to the current signature.
static func signed(dict: Dictionary) -> Dictionary:
	var out: Dictionary = dict.duplicate(true)
	out[SIG_KEY] = signature(dict)
	return out


## True when [param dict] carries a signature that matches its current protected fields.
## A missing signature is invalid (fail-closed).
static func verify(dict: Dictionary) -> bool:
	if not dict.has(SIG_KEY):
		return false
	var expected: String = signature(dict)
	if expected.is_empty():
		return false
	return _constant_time_eq(str(dict[SIG_KEY]), expected)


# Length-independent-exit compare — avoids leaking match position via timing. Minor for a
# local file, but free and correct.
static func _constant_time_eq(a: String, b: String) -> bool:
	if a.length() != b.length():
		return false
	var diff: int = 0
	for i in a.length():
		diff |= a.unicode_at(i) ^ b.unicode_at(i)
	return diff == 0
