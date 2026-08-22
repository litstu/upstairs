---
name: feedback-response-style
description: User's preferred response style — terse, no code output, no greetings, notify on completion only
metadata:
  type: feedback
---

Do not output code in responses. Minimize comments. Skip greetings and explanations — just notify when finished.

**Why:** User prefers a minimal, silent-operator style.

**How to apply:** All responses should be short status updates or completion notices, no preamble. When using "Split with AI" (dev-agent task dispatch), include the full "Detailed Description" alongside the task title in the reasoning/prompt sent to the agent.
