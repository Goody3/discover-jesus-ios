import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request

from jsonschema import Draft7Validator, FormatChecker
from openapi_schema_validator import OAS30Validator, oas30_format_checker


ROOT = Path(__file__).resolve().parents[1]
CONTRACTS = ROOT / "contracts"
FIXTURES = ROOT / "DiscoverJesus/DiscoverJesusAppTests/Fixtures"
SOURCES = {
    "backend": ("Goody3/discover-jesus-backend", "api/openapi.json", "backend.openapi.json"),
    "actions": ("Goody3/discover-jesus-shared", "schemas/actions.schema.json", "actions.schema.json"),
}


def digest(content):
    return hashlib.sha256(content).hexdigest()


def refresh(args):
    pins = {}
    documents = {}
    for name, (repository, path, filename) in SOURCES.items():
        revision = getattr(args, f"{name}_revision")
        if not re.fullmatch(r"[a-f0-9]{40}", revision):
            raise ValueError(f"{name}: expected a full lowercase commit SHA")
        checkout = getattr(args, f"{name}_checkout")
        if checkout:
            content = subprocess.check_output(["git", "-C", checkout, "show", f"{revision}:{path}"])
        else:
            headers = {"Accept": "application/vnd.github.raw+json"}
            if token := os.environ.get("GITHUB_TOKEN"):
                headers["Authorization"] = f"Bearer {token}"
            request = urllib.request.Request(
                f"https://api.github.com/repos/{repository}/contents/{path}?ref={revision}",
                headers=headers,
            )
            with urllib.request.urlopen(request, timeout=30) as response:
                content = response.read()
        json.loads(content)
        documents[filename] = content
        pins[name] = {"revision": revision, "sha256": digest(content)}
    CONTRACTS.mkdir(exist_ok=True)
    for filename, content in documents.items():
        (CONTRACTS / filename).write_bytes(content)
    (CONTRACTS / "revisions.json").write_text(json.dumps(pins, indent=2) + "\n")
    print("Refreshed pinned inputs. Review contracts and fixtures, then run check.")


def load_contracts():
    pins = json.loads((CONTRACTS / "revisions.json").read_text())
    documents = {}
    for name, (_, _, filename) in SOURCES.items():
        content = (CONTRACTS / filename).read_bytes()
        pin = pins[name]
        if not re.fullmatch(r"[a-f0-9]{40}", pin["revision"]) or digest(content) != pin["sha256"]:
            raise ValueError(f"{filename}: revision/digest mismatch; refresh reviewed inputs")
        documents[name] = json.loads(content)
    return documents


def rejects(validator, value, description):
    if validator.is_valid(value):
        raise AssertionError(f"Negative probe unexpectedly accepted: {description}")


def check():
    documents = load_contracts()
    backend = documents["backend"]
    pages = json.loads((FIXTURES / "page-summaries.json").read_text())
    page = json.loads((FIXTURES / "published-page.json").read_text())
    fixtures = [
        ("/api/pages", "GetPages", pages),
        ("/api/content/pages/{pageId}", "GetPageContent", page),
    ]
    validators = []
    for path, operation_id, value in fixtures:
        operation = backend["paths"][path]["get"]
        if operation["operationId"] != operation_id:
            raise ValueError(f"Operation mapping changed: {path}")
        schema = operation["responses"]["200"]["content"]["application/json"]["schema"]
        validator = OAS30Validator(
            {**schema, "components": backend["components"]},
            format_checker=oas30_format_checker,
        )
        validator.validate(value)
        validators.append(validator)
        print(f"Validated {operation_id} HTTP response fixture")

    action_schema = documents["actions"]
    Draft7Validator.check_schema(action_schema)
    action_validator = Draft7Validator(
        {**action_schema, "$ref": "#/definitions/action"}, format_checker=FormatChecker()
    )
    actions = [section["action"] for section in page["sections"] if "action" in section]
    if not actions:
        raise AssertionError("Navigation fixture coverage is missing")
    for action in actions:
        action_validator.validate(action)
        if action["type"] != "navigate" or action["pageId"] not in {p["publicId"] for p in pages}:
            raise AssertionError("Navigation fixture must target a page-summary UUID")

    for field in ("id", "title", "locale", "version", "sections"):
        invalid = copy.deepcopy(page)
        del invalid[field]
        rejects(validators[1], invalid, f"missing page {field}")
    for field, value in (("id", "invalid-uuid"), ("version", "one"), ("title", None)):
        invalid = {**page, field: value}
        rejects(validators[1], invalid, f"malformed page {field}")
    for field in ("id", "publicId", "slug", "title", "isPublished"):
        invalid = copy.deepcopy(pages)
        del invalid[0][field]
        rejects(validators[0], invalid, f"missing summary {field}")
    rejects(validators[0], [{**pages[0], "publicId": "invalid-uuid"}], "malformed summary UUID")
    rejects(action_validator, {"type": "navigate"}, "missing navigation UUID")
    rejects(action_validator, {"type": "navigate", "pageId": "invalid-uuid"}, "malformed navigation UUID")
    rejects(
        action_validator,
        {"type": "navigate", "pageId": pages[0]["publicId"], "target": "home"},
        "legacy target is not a typed action destination",
    )
    print("Validated navigation projections and 17 negative contract probes")
    print("Section/legacy shapes remain client compatibility examples, not schema guarantees.")


parser = argparse.ArgumentParser(description="Refresh or validate STORY-016 contract fixtures.")
commands = parser.add_subparsers(dest="command", required=True)
commands.add_parser("check")
update = commands.add_parser("refresh")
for source in SOURCES:
    update.add_argument(f"--{source}-revision", required=True)
    update.add_argument(f"--{source}-checkout")
arguments = parser.parse_args()
if arguments.command == "refresh":
    refresh(arguments)
else:
    check()
