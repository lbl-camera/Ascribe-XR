## Pure helpers for SceneManager list-management. No side effects, no
## scene-tree access — easy to unit-test.
class_name SceneManagerHelpers


## Returns the new active index after removing `removed_idx` from a list of
## `list_size` specimens whose current active is `active_idx`.
## Returns -1 if the post-removal list is empty.
static func next_active_after_remove(list_size: int, removed_idx: int, active_idx: int) -> int:
	var new_size := list_size - 1
	if new_size <= 0:
		return -1
	if removed_idx == active_idx:
		# Most-recently-added remaining = new last index.
		return new_size - 1
	if removed_idx < active_idx:
		return active_idx - 1
	return active_idx


## Returns true iff a specimen with `new_scale_mode` may be added to a list
## of currently-open specimens. Empty list always allows; otherwise the new
## mode must match the existing list's mode.
static func can_load_with_scale_mode(open_specimens: Array, new_scale_mode: int) -> bool:
	for spec in open_specimens:
		if spec.scale_mode != new_scale_mode:
			return false
	return true


## Resolve which renderer type to use for a completed dynamic-specimen job.
##
## The runtime result type is authoritative: a dynamic specimen such as
## "AI Generate" may produce a mesh OR a volume, so its catalog metadata type
## is only a static guess (it defaults to "mesh" server-side). When the job
## result carries a type, prefer it; otherwise fall back to the catalog type,
## and finally to "mesh".
static func resolve_specimen_type(result_type: String, metadata_type: String) -> String:
	if not result_type.is_empty():
		return result_type
	if not metadata_type.is_empty():
		return metadata_type
	return "mesh"
