# Use Case: Refresh Feeds

## Overview

**Use Case ID:** UC-003  
**Use Case Name:** Refresh Feeds  
**Primary Actor:** Reader, Scheduler  
**Secondary Actors:** Feed Publisher  
**Goal:** Bring every subscribed feed up to date so that new articles appear and changed articles are updated  
**Trigger:** The Reader asks for a refresh, the app starts, or the 30-minute refresh interval elapses  
**Status:** Approved  

## Preconditions

_None — an empty library and a refresh that is already running are handled when the refresh is requested (A5, A6)._

## Main Success Scenario

1. Reader asks for a refresh, or the Scheduler starts one.
2. System shows that a refresh is running.
3. System requests every subscribed feed from its Feed Publisher at the same time, stating which version of the feed it already has; steps 4 to 7 follow for each feed as its answer arrives.
4. Feed Publisher returns the current feed.
5. System adds new articles as unread and updates the title, link, author, content, snippet, and publication date of articles it already has.
6. System records the feed's version and website and clears an earlier error of the feed.
7. System removes the feed's expired articles (BR-008).
8. Once every feed is handled, System saves the library and shows that the refresh has finished.

## Alternative Flows

### A1: Feed Unchanged

**Trigger:** Feed Publisher reports that the feed has not changed since the version the System already has (step 4)  
**Flow:**

1. System clears an earlier error of the feed and leaves its articles unchanged.
2. System is done with this feed; the other feeds are handled as in step 3.
3. Use case continues at step 8.

### A2: Feed Fails

**Trigger:** Feed Publisher does not answer in time, answers with an error, or returns a document that cannot be read as a feed (step 4)  
**Flow:**

1. System records the problem at the feed and shows it with the feed in the subscription list.
2. System is done with this feed; the other feeds are handled as in step 3 (BR-011).
3. Use case continues at step 8.

### A3: Feed Damaged

**Trigger:** Feed Publisher returns a feed that is damaged after at least one readable article (step 4)  
**Flow:**

1. System adds and updates the articles read before the damage as in step 5, and records the feed as in step 6.
2. System removes no article of the feed (BR-003).
3. System is done with this feed; the other feeds are handled as in step 3.
4. Use case continues at step 8.

### A4: Feed Removed During Refresh

**Trigger:** The Reader unsubscribed from a feed while its refresh was running (step 5)  
**Flow:**

1. System discards the result for that feed.
2. System is done with this feed; the other feeds are handled as in step 3.
3. Use case continues at step 8.

### A5: Refresh Already Running

**Trigger:** A refresh is running when the request arrives (step 1)  
**Flow:**

1. When an import requested the refresh (UC-006), System starts one more refresh once the running refresh has finished (BR-002).
2. Otherwise System ignores the request.
3. Use case ends.

### A6: Library Holds No Feed

**Trigger:** The library holds no feed when the request arrives (step 1)  
**Flow:**

1. System ignores the request.
2. Use case ends.

### A7: Library Cannot Be Saved

**Trigger:** The library cannot be saved (step 8)  
**Flow:**

1. System keeps the refreshed feeds and articles in the library (BR-012).
2. System shows that the refresh has finished.
3. Use case ends.

## Postconditions

### Success Postconditions

- Every feed that returned a complete, readable feed holds its current articles, and its expired articles are removed
- Read and starred states of existing articles are unchanged
- Every feed carries either no error or the problem of its latest refresh
- The library is saved

### Failure Postconditions

- No article changes its read or starred state
- No unread or starred article is removed

## Business Rules

### BR-001: Refresh Schedule

Feeds are refreshed when the app starts and then every 30 minutes while it runs. On iPhone and iPad no refresh runs while the app is in the background; when the interval elapsed in the meantime, the refresh follows as soon as the app returns to the foreground. The Reader can refresh at any time from the toolbar; on the Mac also from the menu or with the keyboard shortcut ⌘R, and on iPhone and iPad also by pulling down a list.

### BR-002: One Refresh at a Time

A refresh request is ignored while another refresh is running; the refresh action is disabled meanwhile. The exception is a refresh an import requests (UC-006): it is not ignored, but one more refresh starts once the running one has finished, so the imported feeds are loaded. At most one such refresh waits at a time.

### BR-003: Supported Feed Formats

RSS 2.0, RSS 1.0, and Atom feeds are accepted. A damaged feed is still accepted when at least one article could be read before the damage; such a feed removes no article, because the articles after the damage cannot be told apart from articles that left the feed.

### BR-004: Article Identity

An article is identified within its feed by the feed's identifier for the item, otherwise by its link, otherwise by its title. An item without any of these is skipped, and a repeated item within one feed is taken once.

### BR-005: Article Title

The article title is the item title as plain text, at most 500 characters: a longer title is cut to 499 characters and ends in an ellipsis (…). An item without a title is named "(Untitled)".

### BR-006: Article Snippet and Content

The content shown is the item's full content, otherwise its summary. The snippet in the list is the plain text of the summary, otherwise of the content, at most 280 characters: a longer snippet is cut to 279 characters and ends in an ellipsis (…).

### BR-007: State Survives Updates

Updating an existing article never changes whether it is read or starred. Its publication date is kept when the feed no longer provides one.

### BR-008: Article Retention

An article expires when it is read, not starred, was first fetched more than 30 days ago, and no longer appears in its complete feed. Starred and unread articles never expire. A feed that is unchanged, fails, or is damaged expires no article.

### BR-009: Unchanged Feeds

A feed that has not changed since the last refresh is not downloaded again.

### BR-010: Response Time Limit

A feed that does not answer within 30 seconds counts as failed for this refresh.

### BR-011: Failures Are Isolated

A failing feed does not stop the refresh of the other feeds. Its problem is kept until a later refresh of that feed succeeds.

### BR-012: Unsaved Refresh Is Kept

When the library cannot be saved after a refresh, the refreshed feeds and articles stay in the library and are saved with its next save. The Reader is not told.

### BR-013: Feed Title Is Kept

A refresh does not change a feed's title; it keeps the title given when the feed was subscribed (UC-001 BR-004) or imported (UC-006 BR-003).
