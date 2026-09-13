# Running-document output

### Running-document mode

When the user provides a running Google Doc and asks for it to be filled:

1. Use the Google Docs skill and connector; read the full tab list and the preceding 2–3 updates before writing.
2. Treat the live document as the strongest voice/template reference: preserve its plain date line, bold section labels, bullets, link style, and approximate density.
3. If the user asks for a mega dump, review, or approval, keep the document read-only. Produce both local artifacts first and wait for explicit approval before creating or replacing a tab.
4. Otherwise, write only the requested empty/latest tab from the recommended T5T, then verify the tab id, content, bullet structure, bold labels, and links through connector readback.
5. If the user later cleans up the draft, compare the edited tab with the generated file. Treat deletions as stronger feedback than wording tweaks, then update selection and voice rules accordingly.
