"""Exact production profiles; neither admits the artificial demonstration box."""
PROFILES = {
    'box': {'ENABLE_AVATAR': 0, 'ENABLE_MINIMAL_BOX': 1, 'DEMO_BOX_ONLY': 0},
    'avatar': {'ENABLE_AVATAR': 1, 'ENABLE_MINIMAL_BOX': 0, 'DEMO_BOX_ONLY': 0},
}


def require_profile(build):
    profile = build.get('face_profile')
    if profile not in PROFILES or build.get('top_parameters') != PROFILES[profile]:
        raise ValueError('Not an exact real-inference face profile')
    return profile


def require_simulation_profile(result, profile, log):
    if profile not in PROFILES:
        raise ValueError('Unknown face profile')
    avatar = profile == 'avatar'
    if (result.get('avatar_boot') is not avatar or result.get('boot_load') is not True
            or result.get('model_preloaded') is not False):
        raise ValueError('Simulation loader/profile differs from hardware')
    import re
    modes = '111' if avatar else '010'
    passes = re.findall(r'^# FACE_SYSTEM_PASS ([^\n]+)', log, re.M)
    if len(passes) != 1 or f'modes={modes}' not in passes[0].split():
        raise ValueError('Simulation lacks full-pixel mode coverage')
    if avatar:
        oracle = result.get('avatar_oracle', {})
        values = [oracle.get(k) for k in ('covered_pixels', 'changed_pixels')]
        if result.get('expected_faces') == 1:
            if any(type(v) is not int or v <= 0 for v in values):
                raise ValueError('Avatar oracle does not change visible pixels')
        elif values != [0, 0]:
            raise ValueError('No-face oracle must contain no avatar pixels')
