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
**Resolved in:** UC-001 BR-004, UC-003 BR-005, UC-003 BR-006

## OQ-002: What happens to the refresh interval while the app is in the background?

**Element:** UC-003 BR-001
**Raised by:** /use-case-spec, 2026-11-11
**Blocking:** No
**Status:** Resolved

BR-001 said the interval "pauses" in the background on iPhone and iPad, without saying whether the app refreshes,
resumes the remaining time, or restarts the interval when it returns to the foreground.

**Assumed:** No refresh runs in the background; when the interval elapsed in the meantime, the refresh follows as
soon as the app returns to the foreground.

**Answer:** Confirmed, as assumed.
**Answered by:** Simon Martinelli, 2026-11-11
**Resolved in:** UC-003 BR-001

## OQ-003: Does a refresh update the feed title?

**Element:** UC-003 BR-013
**Raised by:** /use-case-spec, 2026-11-11
**Blocking:** No
**Status:** Resolved

The refresh records the feed's version and website, but the specification did not say whether the feed's own title
replaces the title given at subscription or import.

**Assumed:** A refresh keeps the feed title given at subscription (UC-001 BR-004) or import (UC-006 BR-003).

**Answer:** Confirmed, as assumed.
**Answered by:** Simon Martinelli, 2026-11-11
**Resolved in:** UC-003 BR-013

## OQ-004: On which platforms can the Reader refresh from the menu and by pulling down a list?

**Element:** UC-003 BR-001
**Raised by:** /use-case-spec, 2026-11-12
**Blocking:** No
**Status:** Resolved

BR-001 named "the toolbar, the menu, or by pulling down a list" without a platform. The Mac has a menu bar but no
pull-down gesture in its lists; iPhone has no menu bar, and iPad shows one only with a keyboard attached. Readings:
(a) the menu on the Mac only, pulling down on iPhone and iPad only; (b) the menu also on iPad; (c) every way on every
platform where it exists.

**Assumed:** (a) — the toolbar everywhere; the menu on the Mac; pulling down a list on iPhone and iPad.

**Answer:** Confirmed (a).
**Answered by:** Simon Martinelli, 2026-11-12
**Resolved in:** UC-003 BR-001

## OQ-005: May the Reader open an article in the browser from the article list?

**Element:** UC-004 A3
**Raised by:** /use-case-implement, 2026-11-12
**Blocking:** No
**Status:** Resolved

A3 offers opening in the browser only for the displayed article (step 5), and A4 offers only sharing and copying the
link from the list (step 3). The app's article list also had an "Open in Browser" item in its context menu, which no
step or flow names. Readings: (a) remove it, opening in the browser is offered for the displayed article only; (b)
keep it and widen A3 to step 3.

**Answer:** (a) — remove the list's "Open in Browser"; the browser opens only from the displayed article and its links.
**Answered by:** Simon Martinelli, 2026-11-12
**Resolved in:** UC-004 A3

## OQ-006: Does an explicitly marked article leave Unread when it was displayed before?

**Element:** UC-005 BR-004
**Raised by:** /use-case-implement, 2026-11-12
**Blocking:** No
**Status:** Resolved

BR-004 lets articles opened by displaying them stay in Unread until another list is selected (UC-004 BR-004), but
an article marked as read leaves Unread at once. It does not say which applies to an article the Reader displayed,
then marked as unread (BR-005), and then marked as read again by the toggle or Mark all as read. Readings: (a) the
explicit mark wins and the article leaves Unread at once, even while it is displayed; (b) every article displayed in
the visit stays in Unread until another list is selected.

**Answer:** (a) — an explicit mark as read, by the toggle or by Mark all as read, removes the article from Unread at
once; only reading by displaying keeps it there.
**Answered by:** Simon Martinelli, 2026-11-12
**Resolved in:** UC-005 BR-004

## OQ-007: Does "moves to the background" apply on the Mac?

**Element:** UC-005 BR-002
**Raised by:** /use-case-coverage, 2026-11-12
**Blocking:** No
**Status:** Resolved

BR-002 saves read and starred changes "at the latest when the app quits or moves to the background" and names no
platform. iPhone and iPad have a background state; a Mac app keeps running when the Reader switches away. Readings:
(a) on the Mac, the app moves to the background when another app becomes active or the app is hidden; (b) the
background clause applies to iPhone and iPad only, and the Mac saves on quit and after 2 seconds.

**Answer:** (a) — on the Mac, pending changes are saved when another app becomes active or the app is hidden.
**Answered by:** Simon Martinelli, 2026-11-12
**Resolved in:** UC-005 BR-002

## OQ-008: Which entry is imported when the file lists the same feed address twice?

**Element:** UC-006 BR-002
**Raised by:** /use-case-spec, 2026-11-13
**Blocking:** No
**Status:** Open

An OPML file can hold the same feed address in several entries, for example in two folders, which BR-001 flattens.
The library allows each feed address only once (`FEED.url` Unique). Readings: (a) the first entry in file order is
imported and the rest are skipped; (b) the last entry wins; (c) the file is rejected as unreadable (A1).

**Assumed:** (a) — only the first entry with that address is imported, and its title is used.
