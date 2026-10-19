#!/usr/bin/env python3
"""Convenience entry point for starting the Mapparaan Transit Planner API."""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from api import main

if __name__ == "__main__":
    main()
