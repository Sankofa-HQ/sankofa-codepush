## Sankofa CodePush Protocol

The Sankofa CodePush Protocol is a Dart library which contains common interfaces used by Sankofa CodePush.

### Regenerating from the OpenAPI spec

Everything under `lib/src/` is generated from the public Sankofa
CodePush OpenAPI spec at [api.sankofa.dev/openapi.json](https://api.sankofa.dev/openapi.json)
(also served as [openapi.yaml](https://api.sankofa.dev/openapi.yaml)
for easier human review) by
[space_gen](https://github.com/eseidel/space_gen). To regenerate
against the latest published spec:

```sh
dart run packages/sankofa_code_push_protocol/tool/gen.dart \
  -i https://api.sankofa.dev/openapi.json \
  -o packages/sankofa_code_push_protocol
```

Hand-written files (`lib/extensions/`, `lib/sankofa_code_push_protocol.dart`)
are left untouched by the generator. The version of space_gen in use is
pinned in `pubspec.yaml`.
