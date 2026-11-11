# Use Case: Track Read and Starred Articles

## Overview

**Use Case ID:** UC-005  
**Use Case Name:** Track Read and Starred Articles  
**Primary Actor:** Reader  
**Goal:** Mark articles as read or unread and star the ones worth keeping, so the Reader knows what is left to read and finds important articles again  
**Trigger:** The Reader chooses to change the read or starred state of an article or a list  
**Status:** Draft  

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

1. System leaves the library unchanged.
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

Read and starred changes are saved at most 2 seconds after the last change, and at the latest when the app quits or moves to the background.

### BR-003: Starred Articles Are Kept

A starred article never expires (UC-003 BR-008); it is removed only when its feed is unsubscribed (UC-002 BR-001).
