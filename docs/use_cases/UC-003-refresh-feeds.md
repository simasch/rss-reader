# Use Case: Refresh Feeds

## Overview

**Use Case ID:** UC-003  
**Use Case Name:** Refresh Feeds  
**Primary Actor:** Reader, Scheduler  
**Secondary Actors:** Feed Publisher  
**Goal:** Bring every subscribed feed up to date so that new articles appear and changed articles are updated  
**Trigger:** The Reader asks for a refresh, the app starts, or the 30-minute refresh interval elapses  
**Status:** Draft  

## Preconditions

- The library holds at least one feed
- No refresh is running

## Main Success Scenario

1. Reader asks for a refresh, or the Scheduler starts one.
2. System shows that a refresh is running.
3. System requests every subscribed feed from its Feed Publisher at the same time, stating which version of the feed it already has.
4. Feed Publisher returns the current feed.
5. System adds new articles as unread and updates the title, link, author, content, and summary of articles it already has.
6. System records the feed's version and website and clears an earlier error of the feed.
7. System removes the feed's expired articles.
8. System saves the library and shows that the refresh has finished.

## Alternative Flows

### A1: Feed Unchanged

**Trigger:** Feed Publisher reports that the feed has not changed since the version the System already has (step 4)  
**Flow:**

1. System clears an earlier error of the feed and leaves its articles unchanged.
2. Use case continues at step 8.

### A2: Feed Fails

**Trigger:** Feed Publisher does not answer in time, answers with an error, or returns a document that cannot be read as a feed (step 4)  
**Flow:**

1. System records the problem at the feed and shows a warning sign next to it in the subscription list, with the problem as a tooltip.
2. System continues with the other feeds.
3. Use case continues at step 8.

### A3: Refresh Already Running or No Feeds

**Trigger:** A refresh is running or the library holds no feed (step 1)  
**Flow:**

1. System ignores the request.
2. Use case ends.

### A4: Feed Removed During Refresh

**Trigger:** The Reader unsubscribed from a feed while its refresh was running (step 5)  
**Flow:**

1. System discards the result for that feed.
2. Use case continues at step 8.

## Postconditions

### Success Postconditions

- Every reachable feed's articles reflect its current content
- Read and starred states of existing articles are unchanged
- Every feed carries either no error or the problem of its latest refresh
- The library is saved

### Failure Postconditions

- No article of a failed feed is added, changed, or removed

## Business Rules

### BR-001: Refresh Schedule

Feeds are refreshed when the app starts and then every 30 minutes while it runs. On iPhone and iPad the interval pauses while the app is in the background. The Reader can refresh at any time from the toolbar, the menu, or by pulling down a list.

### BR-002: One Refresh at a Time

A refresh request is ignored while another refresh is running; the refresh action is disabled meanwhile.

### BR-003: Supported Feed Formats

RSS 2.0, RSS 1.0, and Atom feeds are accepted. A damaged feed is still accepted when at least one article could be read before the damage.

### BR-004: Article Identity

An article is identified within its feed by the feed's identifier for the item, otherwise by its link, otherwise by its title. An item without any of these is skipped, and a repeated item within one feed is taken once.

### BR-005: Article Title

The article title is the item title as plain text, shortened to 500 characters. An item without a title is named "(Untitled)".

### BR-006: Article Snippet and Content

The content shown is the item's full content, otherwise its summary. The snippet in the list is the plain text of the summary, otherwise of the content, shortened to 280 characters.

### BR-007: State Survives Updates

Updating an existing article never changes whether it is read or starred. Its publication date is kept when the feed no longer provides one.

### BR-008: Article Retention

An article expires when it is read, not starred, was first fetched more than 30 days ago, and no longer appears in its feed. Starred and unread articles never expire.

### BR-009: Unchanged Feeds

A feed that has not changed since the last refresh is not downloaded again.

### BR-010: Response Time Limit

A feed that does not answer within 30 seconds counts as failed for this refresh.

### BR-011: Failures Are Isolated

A failing feed does not stop the refresh of the other feeds. Its problem is kept until a later refresh of that feed succeeds.
