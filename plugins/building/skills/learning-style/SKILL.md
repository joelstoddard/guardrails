---
name: learning-style
description: Set how Claude presents information to you, and takes it in from you, for this session. Styles are reading, seeing (or visual), doing and listening; give one or more.
argument-hint: "<reading|seeing|visual|doing|listening> [...]"
disable-model-invocation: true
---

# Learning style

Active styles: $ARGUMENTS

Apply these styles until the session ends, or until the user runs this command again. A new run replaces the active set; `reading` alone resets to the baseline. With no style given, list the four styles in one line and ask which. For a name not listed below, ask once what the user means, then apply their description.

## A short answer stays short

If the answer fits in a sentence or two, reply in a sentence or two, in every style. A diagram, page or spike is for an abstract concept: options to compare, a data flow, how parts relate. With more than one style active, pick the one style that best carries this reply.

## The reply shape for each style

Keep the next action and any decision in the terminal reply, even when the content is in a page.

Pages and spikes go in the session scratchpad named in the system prompt. If the session names none, create a folder with `mktemp -d` and use that. Never write them inside the repo.

**reading.** Structured text, as the output style already gives.

**seeing** (alias `visual`). The diagram replaces the prose. The reply is, in order:

1. The answer, in one line.
2. The diagram, at the smallest medium that carries it:
   a. A handful of parts and their links: ASCII art in the reply.
   b. More than that: an HTML page in the session scratchpad, opened in the browser. Give its full absolute path.
   c. A design other people must see: a claude.ai Artifact, ONLY WHEN the user asks for something to share.
3. At most three lines on what the diagram cannot show.

**doing.** Build it; do not describe it. Before replying, write a small throwaway spike in the session scratchpad and run it once to prove it runs. For a concept that is not code, such as two architecture options, the spike is a toy simulation: one small script per option that fakes its behaviour, with output the user can compare. The reply is, in order:

1. The answer, in one line.
2. The command to run, with full absolute paths.
3. What to look for in the output.

A spike is throwaway: never committed, and needs no tests. Keeping one is a new request through the normal workflow. Never hand the user an experiment to set up themselves.

**listening.** Keep the text reply. For a reply that carries a concept, also run `say` in the background with a spoken summary of at most three sentences. Pass the summary in single quotes, with any single quote removed from it, so the shell never expands it. Do not speak a one-line answer. If `say` is missing or fails, say so once and fall back to `reading`.

## Taking information in

Read a sketch, photo or screenshot as the main source, and its caption as context for it. When part of an image is unclear, ask about that part: "Does this arrow mean data flows from A to B?" When the user edits a spike, read their edit and what they report from running it.
