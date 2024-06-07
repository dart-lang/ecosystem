## What's this?

A LLM based triage automation system for the dart-lang/sdk repo. It processes
new issues filed against the repo and triages them in the same manner that a
human would. This includes:

- re-summarizing the issue for clarity
- assigning the issues to an `area-` label (first line triage)

## Bot trigger and entry-point

This bot is generally triggered by a GitHub workflow listening for new issues
on the dart-lang/sdk repo.

See https://github.com/dart-lang/sdk/blob/main/.github/workflows/issue-triage.yml.

## Overview

The general workflow of the tool is:

- download the issue information (existing labels, title, first comment)
- ask Gemini to summarize the issue (see [prompts](lib/src/prompts.dart))
- ask Gemini to classify the issue (see [prompts](lib/src/prompts.dart))
- create a comment on the issue ( `@dart-github-bot`) with the summary;
  apply any labels produced as part of the classification

## Tuning

We create a tuned Gemini model in order to improve the performance of
classification. This involves:

- downloading recent, already triaged issues (~800 issues)
- writing them in a format suitable for tuning (either .csv or .jsonl)
- tuning via the Gemini APIs; this gives us a new model name to use when
  calling Gemini (e.g., `model: 'tunedModels/sdk-triage-tuned-prompt-1l96e2n'`)

See [tool/create_tuning_data.dart](tool/create_tuning_data.dart).
