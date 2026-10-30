import modes_service
from fastapi import HTTPException

# ---------------------------------------------------------------------------
# Modes
#
# One document owns dictation/meeting modes, global AI location and app rules.
# The mobile and desktop clients call these endpoints instead of writing
# UserDefaults/profiles themselves.
# ---------------------------------------------------------------------------

def _modes_call(fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except KeyError as exc:
        detail = str(exc).strip("'\"")
        raise HTTPException(status_code=404, detail=detail or "Not found")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


def _resolve_mode_request(mode, mode_id, mode_style, correction_location, self_correction_bool, self_correction_model):
    """When a client sends ``mode_id``, the modes store owns these settings.

    Old clients send neither, so their form values are used unchanged.
    """
    if not mode_id:
        return mode_style, correction_location, self_correction_bool, self_correction_model
    try:
        resolved = modes_service.modes_service.resolve_for_request(mode_id=mode_id, legacy_mode=mode)
    except Exception as exc:
        print(f"[!] Could not resolve mode '{mode_id}': {exc}")
        return mode_style, correction_location, self_correction_bool, self_correction_model
    if not resolved:
        return mode_style, correction_location, self_correction_bool, self_correction_model
    # When a mode is named, the mode owns every one of these settings.
    return (
        resolved.get("style") or mode_style,
        resolved.get("ai_location") or correction_location,
        bool(resolved.get("fix_corrections")),
        resolved.get("self_correction_model") or "",
    )
