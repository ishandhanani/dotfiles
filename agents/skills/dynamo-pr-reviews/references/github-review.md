# GitHub review publication

Prepare the complete review locally with one inline finding per affected diff location. Re-fetch the PR head and diff before posting; the tested commit and each path/line/side must still match. Findings state the failure trigger, outcome, evidence, and smallest response. Use a formal `COMMENT` review unless the user explicitly requests another event.

A request to review code alone does not authorize publication. When publication is already authorized, submit once without an additional approval round. A draft-only request writes a local payload and does not call GitHub mutations. Questions to the author require explicit authorization to communicate them. A clean review needs no outbound comment unless requested.

Write the exact payload to a JSON file, including actual newlines in body strings:

```json
{
  "commit_id": "<verified-tested-head-sha>",
  "event": "COMMENT",
  "body": "<summary and validation>",
  "comments": [
    {"path": "<repository-relative-path>", "line": 1, "side": "RIGHT", "body": "<finding and evidence>"}
  ]
}
```

Use the verified diff line, not the illustrative `1`:

```bash
gh api --method POST "repos/$REPO/pulls/$PR/reviews" --input "$REVIEW_PAYLOAD"
```

If the user explicitly requests a pending review on GitHub, omit `event` entirely in the creation payload. Check the returned state is `PENDING`. When submission is authorized, write `{"event":"COMMENT","body":"<final summary>"}` to a separate JSON file and POST it to `repos/$REPO/pulls/$PR/reviews/$REVIEW_ID/events`. `SUBMIT` is not an accepted event. Creating with `COMMENT` publishes immediately; do not label that operation a draft.

Read back the returned review state, commit, and inline comments. If a write times out, inspect existing reviews before retrying to avoid duplicates. Preserve the publication URL with the local evidence.

API reference: [create review](https://docs.github.com/en/rest/pulls/reviews#create-a-review-for-a-pull-request) and [submit pending review](https://docs.github.com/en/rest/pulls/reviews#submit-a-review-for-a-pull-request).
