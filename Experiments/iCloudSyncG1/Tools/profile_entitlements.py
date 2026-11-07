"""Profile allowlists differ from the exact entitlements claimed by an app.

Apple TN3125: https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles
Accept the observed Apple-issued service wildcard and unordered environment list.
The signed app must still claim only CloudKit and exactly Development.
"""


def _values(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return value
    return []


def allows_cloudkit(signed, profile):
    key = 'com.apple.developer.icloud-services'
    allowed = _values(profile.get(key))
    return signed.get(key) == ['CloudKit'] and ('CloudKit' in allowed or '*' in allowed)


def allows_development(signed, profile):
    key = 'com.apple.developer.icloud-container-environment'
    return signed.get(key) == 'Development' and 'Development' in _values(profile.get(key))


def allows_container(signed, profile, expected):
    key = 'com.apple.developer.icloud-container-identifiers'
    allowed = profile.get(key)
    return (signed.get(key) == [expected] and isinstance(allowed, list)
            and all(isinstance(item, str) for item in allowed) and expected in allowed)
