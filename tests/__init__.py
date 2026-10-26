"""Test package bootstrap.

``unittest discover -s tests`` imports modules top-level, so each test module
also imports ``_bootstrap`` directly. This package keeps ``-m unittest tests.x``
working by putting the tests directory on sys.path first.
"""

import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import _bootstrap  # noqa: E402,F401
