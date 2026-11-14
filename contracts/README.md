# iOS contract fixtures

STORY-016 verifies only the representations the app actually consumes.
[revisions.json](revisions.json) identifies the full source commits and SHA-256
digests of the byte-for-byte contract copies. Fixtures are authored, synthetic
test examples, not captured backend responses or personal data.

## Mapping and coverage

| Fixture / projection | Source contract | App consumer | Validation |
| --- | --- | --- | --- |
| [page-summaries.json](../DiscoverJesus/DiscoverJesusAppTests/Fixtures/page-summaries.json) | Backend OpenAPI `GET /api/pages`, `GetPages`, 200 JSON array of `PageSummary` | `PagesViewModel`, `PageSummary` | OpenAPI 3.0 response schema, required fields and UUID format; Swift decoding |
| [published-page.json](../DiscoverJesus/DiscoverJesusAppTests/Fixtures/published-page.json) | Backend OpenAPI `GET /api/content/pages/{pageId}?locale=...`, `GetPageContent`, 200 JSON `PageContentResponse` | `PageContentLoader`, `LocalizedPageContent` | OpenAPI envelope, required fields and UUID format; Swift decoding and classification |
| Each top-level `sections[*].action` in the published-page fixture | Shared actions schema `#/definitions/action` | `LocalizedPageSectionAction`, UUID navigation | Explicitly selected `navigate` action projection; schema validation plus destination UUID lookup in the summary fixture; Swift UUID preference |

The backend snapshot is from the merged STORY-015 metadata prerequisite,
revision `dc977a8d61b789bc33683f6d2b0c41cac8f71d8f`. It is not the separate
shared OpenAPI document. The action schema is copied from shared revision
`f644127e53d421c9c4c8fb3c5e42663c11e14a1a`. This is an explicit test mapping
of the selected typed navigation action only, not a claim that the entire
backend payload implements the shared schemas.

## Deliberate gaps and compatibility

- Backend OpenAPI leaves `sections` opaque (`{}`). It does not specify section
  arrays, component fields, legacy metadata, or navigation internals. The
  app's section-array and per-section `type` requirements are client assumptions,
  tested separately, not guarantees derived from this HTTP contract.
- The fixture covers the app's button, header, text, list, navigation bar,
  suppressed NBButton, BibleVerse, image, legacy `source.legacyType` override,
  and unknown-component classification. These are client compatibility examples.
  They are not validated against the shared component enum: that would reject
  supported legacy types and conflate representations.
- `sourceComponentId`, `headerLevel`, `attribute`, styling roles, children,
  image fields, and legacy props have Swift regression assertions but no
  authoritative section-schema mapping. Nested rendering and arbitrary dynamic
  JSON conformance are not established by these tests.
- Missing `navigate.pageId` fails the selected shared action schema, while the
  existing Swift decoder accepts it as optional. A dedicated test documents that
  gap; the loader/renderer is not made stricter by this story.
- UUID navigation wins over legacy slug props; case-insensitive slug fallback
  remains. Existing tests remain unchanged. No fallback removal is authorized.
- The app consumes neither shared `content.blocks` nor the legacy
  `GET /api/pages/{slug}` detail response; neither is silently mapped here.
- Fixtures cannot prove live backend response conformance, destination
  availability, or rendering support for every future component.

## Validate locally and in CI

Python 3.12 and Xcode are used in CI:

```sh
python3 -m venv .venv-contracts
.venv-contracts/bin/python -m pip install -r scripts/requirements-contracts.txt
.venv-contracts/bin/python scripts/check-contracts.py check
xcodebuild \
  -workspace DiscoverJesusPlatform.xcworkspace \
  -scheme DiscoverJesus \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO build test
```

The validator checks pinned-input digests, both HTTP fixtures, typed navigation
projections, and 17 negative contract probes. Swift tests load the same bundled
fixtures and cover missing/malformed fields, unknown components, and documented
compatibility behavior. Invalid fixture JSON fails validation explicitly.
CI validates before building/testing; it needs no backend, sibling checkout,
or cross-repository token. Installing Python dependencies still needs the
package registry, just as a normal CI dependency restore does.

## Refresh intentionally

Choose reviewed full commit SHAs, then retrieve their exact files through
GitHub's contents API:

```sh
.venv-contracts/bin/python scripts/check-contracts.py refresh \
  --backend-revision <full-backend-sha> \
  --actions-revision <full-shared-sha>
.venv-contracts/bin/python scripts/check-contracts.py check
```

For private repositories, supply a read-only `GITHUB_TOKEN` in the environment,
never in source files or command arguments. Alternatively, add
`--backend-checkout /path/to/discover-jesus-backend` and
`--actions-checkout /path/to/discover-jesus-shared`; the script uses `git show`
at the specified commits, not potentially modified working-tree files.

Review the source contract differences, revision/digests, fixture contents,
mapping/gaps, and Swift assertions together; rerun validation and all iOS tests.
The refresh command does not rewrite fixtures or silently adopt the latest
branch. The check command does not rewrite inputs. A manually altered contract
with a stale digest must fail, not be auto-accepted.
