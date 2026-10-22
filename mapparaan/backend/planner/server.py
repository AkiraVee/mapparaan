#!/usr/bin/env python3
"""Compatibility entry point for the shared Mapparaan transit API."""

import argparse
import os

if __package__:
    from .api import run_server
else:
    from api import run_server


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_data = os.path.normpath(os.path.join(here, "..", "..", "data"))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", default=default_data, help="Path to the data/ folder")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Use 0.0.0.0 only on a trusted network and set MAPPARAAN_ALLOWED_ORIGINS.",
    )
    args = parser.parse_args()
    run_server(host=args.host, port=args.port, data_dir=args.data)


if __name__ == "__main__":
    main()
