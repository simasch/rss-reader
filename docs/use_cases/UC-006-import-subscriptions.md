# Use Case: Import Subscriptions

## Overview

**Use Case ID:** UC-006  
**Use Case Name:** Import Subscriptions  
**Primary Actor:** Reader  
**Goal:** Take over the subscriptions of another feed reader from an exported subscription file, without adding each feed by hand  
**Trigger:** The Reader chooses to import a subscription file  
**Status:** Approved  

## Preconditions

- The Reader has a subscription file exported from a feed reader

## Main Success Scenario

1. Reader chooses to import subscriptions.
2. System asks for the subscription file.
3. Reader selects the file.
4. System reads every feed entry of the file with its title, feed address, and website, and checks each feed address (BR-005).
5. System adds every feed the Reader is not yet subscribed to (BR-002) and sorts the subscription list by title.
6. System saves the library.
7. System refreshes all feeds (UC-003).

## Alternative Flows

### A1: Unreadable File

**Trigger:** The file cannot be read as a subscription file (step 4)  
**Flow:**

1. System displays an error message that describes the problem.
2. Use case ends.

### A2: No New Feeds

**Trigger:** Every feed of the file is already subscribed, or the file holds no feed entry with a valid feed address (step 5)  
**Flow:**

1. System leaves the library unchanged and does not refresh.
2. Use case ends.

### A3: Reader Cancels

**Trigger:** Reader cancels the file selection (step 3)  
**Flow:**

1. Use case ends.

### A4: Library Cannot Be Saved

**Trigger:** The library cannot be saved (step 6)  
**Flow:**

1. System removes the imported feeds from the library again (BR-006).
2. System displays a message that the subscriptions could not be imported.
3. Use case ends.

## Postconditions

### Success Postconditions

- Every feed of the file that was not subscribed before is in the library
- The library is saved
- A refresh of all feeds has started, or is queued behind the running refresh (UC-003 BR-002)

### Failure Postconditions

- No feed is added to the library

## Business Rules

### BR-001: Supported File

The file is an OPML subscription list. Folders in the file are flattened: every outline entry with a feed address becomes a feed, whatever folder it is in.

### BR-002: No Duplicates on Import

An entry whose feed address is already subscribed is skipped (UC-001 BR-002). When the file holds the same feed address more than once, only its first entry is imported. Addresses are compared after they are checked by BR-005.

### BR-003: Imported Feed Title

The feed title is the entry's title, otherwise its text, otherwise the host name of the feed address; a title or text that holds only spaces counts as missing. The title is plain text, at most 200 characters: a longer title is cut to 199 characters and ends in an ellipsis (…), as on subscribe (UC-001 BR-004).

### BR-004: Order After Import

Imported feeds are listed by the subscription order (UC-001 BR-005).

### BR-005: Feed Addresses on Import

Each entry's feed address is accepted by the same rules as on subscribe (UC-001 BR-001): spaces are ignored, a `feed:` address is turned into the web address that follows it, and an address without a scheme is completed to `https://`. An entry whose address is still not an `http` or `https` address with a host name is skipped; the other entries are imported.

### BR-006: Only Saved Imports Are Added

When the library cannot be saved after the import, none of the imported feeds is added: they are removed from the library again, and no refresh is started.
