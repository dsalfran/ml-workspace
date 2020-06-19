#!/usr/bin/python

"""
Configure and run tools
"""

from subprocess import call
import os
import sys

# Enable logging
import logging

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO,
    stream=sys.stdout,
)

log = logging.getLogger(__name__)

ENV_RESOURCES_PATH = os.getenv("RESOURCES_PATH", "/resources")
ENV_WORKSPACE_HOME = os.getenv("WORKSPACE_HOME", "/workspace")
HOME = os.getenv("HOME", "/root")

DESKTOP_PATH = HOME + "/Desktop"

# Get jupyter token
ENV_AUTHENTICATE_VIA_JUPYTER = os.getenv("AUTHENTICATE_VIA_JUPYTER", "false")

token_parameter = ""
if ENV_AUTHENTICATE_VIA_JUPYTER.lower() == "true":
    # Check if started via Jupyterhub -> JPY_API_TOKEN is set
    ENV_JPY_API_TOKEN = os.getenv("JPY_API_TOKEN", None)
    if ENV_JPY_API_TOKEN:
        token_parameter = "?token=" + ENV_JPY_API_TOKEN
elif ENV_AUTHENTICATE_VIA_JUPYTER and ENV_AUTHENTICATE_VIA_JUPYTER.lower() != "false":
    token_parameter = "?token=" + ENV_AUTHENTICATE_VIA_JUPYTER
