# Use Case: Unsubscribe from Feed

## Overview

**Use Case ID:** UC-002  
**Use Case Name:** Unsubscribe from Feed  
**Primary Actor:** Reader  
**Goal:** Remove a feed the Reader no longer wants to follow, together with its articles  
**Trigger:** The Reader chooses to unsubscribe from a feed in the subscription list  
**Status:** Approved  

## Preconditions

- The library holds at least one feed

## Main Success Scenario

1. Reader chooses to unsubscribe from a feed in the subscription list.
2. System removes the feed and all of its articles from the library (BR-001).
3. System updates the subscription list and the unread counts.
4. System saves the library.

## Alternative Flows

### A1: Removed Feed's Article List Was Displayed

**Trigger:** The article list of the removed feed was displayed (step 2)  
**Flow:**

1. System displays the Unread list instead.
2. When one of the feed's articles was displayed in the article view, System displays that no article is selected.
3. Use case continues at step 3.

### A2: Article of the Removed Feed Was Displayed in Another List

**Trigger:** Unread, All Articles, or Starred was displayed and held articles of the removed feed (step 2)  
**Flow:**

1. System removes the feed's articles from the displayed list, including articles kept there after reading (UC-004 BR-004).
2. When one of them was displayed in the article view, System displays that no article is selected.
3. Use case continues at step 3.

### A3: Library Cannot Be Saved

**Trigger:** The library cannot be saved (step 4)  
**Flow:**

1. System puts the feed and its articles back into the library (BR-002).
2. System updates the subscription list, the unread counts, and the displayed article list (BR-002).
3. System displays a message that the feed could not be unsubscribed.
4. Use case ends.

## Postconditions

### Success Postconditions

- The feed is no longer in the library
- None of the feed's articles remain in the library, starred ones included
- The library is saved

### Failure Postconditions

- The library is unchanged

## Business Rules

### BR-001: Articles Leave with Their Feed

Unsubscribing removes every article of the feed, including read and starred ones. The removal is not confirmed beforehand and cannot be undone.

### BR-002: Only Saved Unsubscribes Take Effect

A feed whose removal cannot be saved stays subscribed: it and its articles are put back with their read and starred states. The display does not return to its earlier state: the list displayed now stays selected and shows the restored articles by its own rules (UC-004 BR-001), so read articles that were kept in Unread before (UC-004 BR-004) do not reappear there, and an article view cleared by the removal stays cleared.
