# Use Case: Track Read and Starred Articles

## Overview

**Use Case ID:** UC-005  
**Use Case Name:** Track Read and Starred Articles  
**Primary Actor:** Reader  
**Goal:** Mark articles as read or unread and star the ones worth keeping, so the Reader knows what is left to read and finds important articles again  
**Trigger:** The Reader chooses to change the read or starred state of an article or a list  
**Status:** Done  

## Preconditions

- The library holds at least one article

## Main Success Scenario

1. Reader chooses an article in the list or the displayed article.
2. Reader chooses to toggle its read state.
3. System marks the article as unread if it was read, or as read if it was unread.
4. System updates the article list and the unread counts.
5. System saves the change.

## Alternative Flows

### A1: Toggle Star

**Trigger:** Reader chooses to star or unstar the article instead (step 2)  
**Flow:**

1. System stars the article if it was not starred, or removes the star if it was.
2. System updates the Starred list and the star shown with the article.
3. Use case continues at step 5.

### A2: Mark All as Read

**Trigger:** Reader chooses to mark all articles of the displayed list as read instead (step 1)  
**Flow:**

1. System marks every unread article of the displayed list as read.
2. Use case continues at step 4.

### A3: Nothing to Mark

**Trigger:** The displayed list holds no unread article (step 1 of A2)  
**Flow:**

1. System leaves the library unchanged; in Unread, the articles read by displaying them during the visit leave the list (BR-004).
2. Use case ends.

### A4: Saving Fails

**Trigger:** The library cannot be saved (step 5)  
**Flow:**

1. System keeps the change in effect without telling the Reader and saves it with the next save of the library (BR-002).
2. Use case ends.

## Postconditions

### Success Postconditions

- The chosen articles carry the new read or starred state
- The change is saved

### Failure Postconditions

- No article outside the chosen article or the displayed list changes its state

## Business Rules

### BR-001: Mark All Is Limited to the List

Mark all as read affects only the articles of the displayed list: one feed, the starred articles, the unread articles, or all articles.

### BR-002: Saving State Changes

Read and starred changes are saved at most 2 seconds after the last change, and at the latest when the app quits or moves to the background; on the Mac, the app moves to the background when another app becomes active or the app is hidden. When the library cannot be saved, the changes stay in effect and are saved with the next save of the library; the Reader is not told.

### BR-003: Starred Articles Are Kept

A starred article never expires (UC-003 BR-008); it is removed only when its feed is unsubscribed (UC-002 BR-001).

### BR-004: The List Follows a Change at Once

An article that no longer belongs to the displayed list after a change leaves it at once: an article marked as read leaves Unread, and an unstarred article leaves Starred. Mark all as read in Unread leaves the list empty: the articles it marks leave it, and so do the articles read by displaying them during the visit, also when it marks none (A3). Apart from that, articles read by displaying them stay in Unread until the Reader selects another list (UC-004 BR-004). An article the Reader marks as read by the toggle leaves Unread at once even when it was displayed before in the same visit, and also while it is displayed.

### BR-005: Unread Stays Unread While Displayed

An article the Reader marks as unread while it is displayed stays unread; it is marked as read again only when the Reader displays it anew (UC-004 BR-003).

### BR-006: The Displayed Article Stays When It Leaves the List

When the displayed article leaves the displayed list (BR-004), it stays displayed until the Reader selects or moves to another article. Moving to the previous or next article (UC-004 step 6) goes to the articles that were next to it in the list.
