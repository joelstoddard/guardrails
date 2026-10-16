---
type: regex
target: last_message
pattern: '## Intent\s*\n\s*> \[!IMPORTANT\]\s*\n> Author: replace this block with the mission these changes drive towards, in your own words\. An agent never writes this section\.\s*\n\s*## What'
---

Passes when the body opens with the Intent placeholder, verbatim and with nothing written into it, before What. Only the author writes the Intent.
