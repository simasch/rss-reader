# Open Questions

Questions about the specification that the specification does not answer yet. A question is `Resolved` only when
the answer is in the specification itself; **Resolved in** names where. Resolved and withdrawn questions stay as
history.

## OQ-001: Does "shortened to 200 characters" include an ellipsis?

**Element:** UC-001 BR-004
**Raised by:** /use-case-implement, 2026-11-11
**Blocking:** No
**Status:** Resolved

BR-004 shortens the feed title to 200 characters; the entity model says "at most 200 characters". The code cut at
200 and appended "…", giving 201. The same wording is used for article titles (UC-003 BR-005, 500) and snippets
(UC-003 BR-006, 280). Readings: (a) 199 characters plus "…", 200 in total; (b) a hard cut at 200 without an
ellipsis; (c) 200 characters plus "…".

**Answer:** (a) — cut to one character less than the limit and append "…", so the result is at most the limit.
Applies to every "shortened to N characters" rule.
**Answered by:** Simon Martinelli, 2026-11-11
**Resolved in:** UC-001 BR-004
