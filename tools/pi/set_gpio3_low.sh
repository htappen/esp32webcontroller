#!/usr/bin/env bash
set -euo pipefail

pinctrl set 3 op dl
pinctrl get 3

