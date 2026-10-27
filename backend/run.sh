#!/bin/bash
# Start the Sabak backend. First run creates config.json with a random admin key and prints it.
cd "$(dirname "$0")"
exec python3 server.py
