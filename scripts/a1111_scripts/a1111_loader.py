#!/usr/bin/env python3
# Added: 2025-04-14T18:45:00-04:00 - Model loader for Automatic1111

import argparse
import requests  # type: ignore
import json

parser = argparse.ArgumentParser(description='Load a model into Automatic1111')
parser.add_argument('-m', '--model', type=str, required=True, help='Model name')
args = parser.parse_args()

url = "http://localhost:3001/sdapi/v1/options"
response = requests.get(url)
options = json.loads(response.text)
options["sd_model_checkpoint"] = args.model
requests.post(url, json=options)
print(f"Loaded model: {args.model}")
