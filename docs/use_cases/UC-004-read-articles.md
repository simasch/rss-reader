# Use Case: Read Articles

## Overview

**Use Case ID:** UC-004  
**Use Case Name:** Read Articles  
**Primary Actor:** Reader  
**Goal:** Browse the articles of all or of selected feeds and read them, so the Reader keeps up with new content  
**Trigger:** The Reader opens the app or selects a list in the sidebar  
**Status:** Done  

## Preconditions

_None — an empty library is handled in A1._

## Main Success Scenario

1. System displays the sidebar with the smart lists Unread, All Articles, and Starred, the subscribed feeds, and their unread counts, with Unread selected.
2. Reader selects a smart list or a feed.
3. System displays the articles of the selection, newest first, each with its feed, date, title, snippet, read state, and star.
4. Reader selects an article.
5. System marks the article as read and displays it with its feed, author, publication date, title, and content.
6. Reader moves to the previous or next article in the list.
7. System marks that article as read and displays it.
8. Reader repeats steps 6 and 7 until done.

## Alternative Flows

### A1: No Feeds Yet

**Trigger:** The library holds no feed (step 1)  
**Flow:**

1. System displays "No Feeds" with an offer to add a feed.
2. Reader chooses to add a feed and continues with UC-001.
3. Use case ends.

### A2: List Is Empty

**Trigger:** The selection contains no article (step 3)  
**Flow:**

1. System displays "You're all caught up." for the Unread list and "Nothing here yet." for any other list.
2. Use case continues at step 2.

### A3: Open in Browser

**Trigger:** Reader chooses to open the displayed article, or clicks a link in it (step 5)  
**Flow:**

1. System opens the article's web page, or the linked page, in the default browser.
2. Use case continues at step 6.

### A4: Share or Copy a Link from the List

**Trigger:** Reader chooses to share an article of the list or to copy its link (step 3)  
**Flow:**

1. System passes the article's link to the share sheet, or copies it to the clipboard, as the Reader chose.
2. Use case continues at step 4.

### A5: Share or Copy the Displayed Article's Link

**Trigger:** Reader chooses to share the displayed article or to copy its link (step 5)  
**Flow:**

1. System passes the article's link to the share sheet, or copies it to the clipboard, as the Reader chose.
2. Use case continues at step 6.

### A6: Reader Selects Another List

**Trigger:** Reader selects another smart list or feed (step 6)  
**Flow:**

1. System clears the article selection and forgets which articles were read during the visit.
2. Use case continues at step 3.

## Postconditions

### Success Postconditions

- Every article the Reader opened is marked as read
- The unread counts reflect the opened articles

### Failure Postconditions

- No article the Reader did not open changes its read state

## Business Rules

### BR-001: Smart Lists

Unread shows all unread articles, All Articles shows every article, Starred shows the starred articles, and a feed shows all articles of that feed.

### BR-002: Article Order

Articles are listed newest first by publication date; an article without a publication date is ordered by the time it was first fetched.

### BR-003: Opening Marks as Read

Displaying an article marks it as read; the change is saved as BR-008 says.

### BR-004: Stable Unread List

Articles read during a visit to a list stay in the Unread list until the Reader selects another list, so the list does not shift and the Reader can move back to them.

### BR-005: Safe Article Display

Article content is displayed without running scripts it contains. Links in the content open in the default browser, not inside the app.

### BR-006: Unread Counts

The sidebar shows the number of unread articles for each feed and the total for the Unread list.

### BR-007: Open and Share Need a Link

Opening in the browser, sharing, and copying the link are offered only for articles that have a link. Sharing and copying the link are offered on every platform.

### BR-008: Saving Read State

An article marked as read by displaying it is saved like any other read change (UC-005 BR-002). When the library cannot be saved, the article stays read and is saved with the next save of the library; the Reader is not told.
