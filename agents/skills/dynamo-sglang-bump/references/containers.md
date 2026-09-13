# Runtime image references

Inspect current container manifests and upstream published tags for the requested release and CUDA variants. Pip versions, post releases, RC tags, and runtime image tags do not necessarily match. SGLang's base-image and runtime-image workflows can publish at different times.

```bash
docker buildx imagetools inspect "lmsysorg/sglang:$RUNTIME_TAG"
```

Use supplied tags exactly after verifying they resolve. When tags are unspecified, discover the release's available runtime variants and infer only an unambiguous match with the requested configuration. Ask about an unresolved variant. If a required runtime image is unavailable, inspect the runtime release workflow and surface the choice to wait or defer that container portion; continue independent pip/source work. Do not dispatch upstream release jobs without authorization.

Search all current manifests for old runtime references, including `container/context.yaml`, generated Dockerfiles, compliance tables, and runtime templates when present. Use the repository's generation workflow for generated files. Remove a version-specific packaging workaround only after verifying the new image fixes it. Record any deferred image updates in the draft PR so the tested scope is clear.
