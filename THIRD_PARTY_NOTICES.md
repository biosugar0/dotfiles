# Third-Party Notices

This repository contains files adapted from third-party projects.
The following notices are required by the upstream licenses.

---

## openai/codex-plugin-cc

- Upstream: https://github.com/openai/codex-plugin-cc
- License: Apache License, Version 2.0
- License text (committed copy): [`LICENSES/Apache-2.0.txt`](./LICENSES/Apache-2.0.txt)
- License URL: https://www.apache.org/licenses/LICENSE-2.0

NOTICE (preserved from upstream):

```
Copyright 2026 OpenAI

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

Files in this repository derived from `codex-plugin-cc`:

- `dot_config/claude/skills/codex-tmux/templates/adversarial-review.md`
  - Adapted from `plugins/codex/prompts/adversarial-review.md`
  - Modifications: removed `<structured_output_contract>` JSON schema block;
    replaced with `<output_format>` for human-readable findings; removed
    `{{REVIEW_INPUT}}` / `{{TARGET_LABEL}}` / `{{USER_FOCUS}}` placeholders.

The derivative file is distributed under the same Apache-2.0 license as the
upstream source. Per Apache-2.0 §4, the modifications above are noted in this
file and in the file-level header of the derivative file itself.
