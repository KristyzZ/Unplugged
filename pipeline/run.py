#!/usr/bin/env python3
"""Run from anywhere:  python3 pipeline/run.py crawl | load-registry | poll | report | export"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from evdata.cli import main  # noqa: E402

sys.exit(main())
