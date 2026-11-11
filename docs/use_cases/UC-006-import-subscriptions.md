# Use Case: Import Subscriptions

## Overview

**Use Case ID:** UC-006  
**Use Case Name:** Import Subscriptions  
**Primary Actor:** Reader  
**Goal:** Take over the subscriptions of another feed reader from an exported subscription file, without adding each feed by hand  
**Trigger:** The Reader chooses to import a subscription file  
**Status:** Draft  

## Preconditions

- The Reader has a subscription file exported from a feed reader

## Main Success Scenario

1. Reader chooses to import subscriptions.
2. System asks for the subscription file.
3. Reader selects the file.
4. System reads every feed entry of the file with its title, feed address, and website.
5. System adds every feed the Reader is not yet subscribed to and sorts the subscription list by title.
6. System saves the library.
7. System refreshes all feeds (UC-003).

## Alternative Flows

### A1: Unreadable File

**Trigger:** The file cannot be read as a subscription file (step 4)  
**Flow:**

1. System displays an error message that describes the problem.
2. Use case ends.

### A2: No New Feeds

**Trigger:** Every feed of the file is already subscribed, or the file holds no feed entry (step 5)  
**Flow:**

1. System leaves the library unchanged and does not refresh.
2. Use case ends.

### A3: Reader Cancels

**Trigger:** Reader cancels the file selection (step 3)  
**Flow:**

1. Use case ends.

## Postconditions

### Success Postconditions

- Every feed of the file that was not subscribed before is in the library
- The library is saved
- A refresh has loaded the articles of the new feeds

### Failure Postconditions

- No feed is added to the library

## Business Rules

### BR-001: Supported File

The file is an OPML subscription list. Folders in the file are flattened: every outline entry with a feed address becomes a feed, whatever folder it is in.

### BR-002: No Duplicates on Import

An entry whose feed address is already subscribed is skipped (UC-001 BR-002).

### BR-003: Imported Feed Title

The feed title is the entry's title, otherwise its text, otherwise the host name of the feed address.

### BR-004: Order After Import

Imported feeds are listed by the subscription order (UC-001 BR-005).
