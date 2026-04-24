## Binary envelope parser for the ascribe-link wire format.
##
## Layout:
##     <4-byte little-endian uint32: preamble_length>
##     <preamble_length bytes: UTF-8 JSON preamble>
##     <raw bytes: one or more contiguous data blocks>
class_name BinaryEnvelope
extends RefCounted

const MEDIA_TYPE := "application/x-ascribe-envelope-v1"


## Parse the envelope header.
##
## Returns a Dictionary:
##   - On success: {"preamble": Dictionary, "offset": int}
##   - On failure: {"error": String}
static func parse(body: PackedByteArray) -> Dictionary:
	if body.size() < 4:
		return {"error": "envelope truncated: missing length prefix"}
	var preamble_len := body.decode_u32(0)
	if body.size() < 4 + preamble_len:
		return {"error": "envelope truncated: preamble incomplete (claimed %d bytes, got %d)" % [preamble_len, body.size() - 4]}
	var preamble_bytes := body.slice(4, 4 + preamble_len)
	var preamble_str := preamble_bytes.get_string_from_utf8()
	var preamble = JSON.parse_string(preamble_str)
	if preamble == null or not (preamble is Dictionary):
		return {"error": "envelope: invalid JSON preamble"}
	return {"preamble": preamble, "offset": 4 + preamble_len}
