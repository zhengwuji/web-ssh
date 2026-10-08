"""Strict, CSS-free terminal appearance settings shared by storage and HTTP."""

import math
import re


_COLOR_KEYS = frozenset({
    'background', 'foreground', 'cursor_color', 'selection_background',
})
_KEYS = _COLOR_KEYS | {
    'font_family', 'font_size', 'line_height', 'letter_spacing',
    'font_weight', 'background_opacity', 'cursor_style', 'cursor_blink',
}
# Compiled once: validation runs on every settings read and write.
_COLOR_PATTERN = re.compile(r'#[0-9a-fA-F]{6}')
_FONT_FAMILY_PATTERN = re.compile(r'[A-Za-z0-9 _-]{1,64}')


def valid_terminal_appearance(value):
    """Accept optional typed overrides; an empty object follows the app theme."""
    if not isinstance(value, dict) or set(value) - _KEYS:
        return False
    for key, item in value.items():
        if key in _COLOR_KEYS:
            if item is not None and (
                not isinstance(item, str)
                or _COLOR_PATTERN.fullmatch(item) is None
            ):
                return False
        elif key == 'font_family':
            if (
                not isinstance(item, str)
                or _FONT_FAMILY_PATTERN.fullmatch(item) is None
            ):
                return False
        elif key == 'font_size':
            if item is not None and (type(item) is not int or not 8 <= item <= 32):
                return False
        elif key in {'line_height', 'letter_spacing'}:
            lower, upper = (1, 2) if key == 'line_height' else (-1, 3)
            if (
                type(item) not in (int, float)
                or not lower <= item <= upper
                or not math.isfinite(item)
            ):
                return False
        elif key == 'font_weight':
            if not isinstance(item, str) or item not in {'normal', 'bold'}:
                return False
        elif key == 'background_opacity':
            if type(item) is not int or not 0 <= item <= 100:
                return False
        elif key == 'cursor_style':
            if (
                not isinstance(item, str)
                or item not in {'block', 'underline', 'bar'}
            ):
                return False
        elif key == 'cursor_blink' and type(item) is not bool:
            return False
    return True
