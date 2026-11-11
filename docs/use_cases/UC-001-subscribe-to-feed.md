# Use Case: Subscribe to Feed

## Overview

**Use Case ID:** UC-001  
**Use Case Name:** Subscribe to Feed  
**Primary Actor:** Reader  
**Secondary Actors:** Feed Publisher  
**Goal:** Add a news feed to the library by entering its address or the address of its website, so its articles appear in the reader  
**Trigger:** The Reader chooses to add a feed  
**Status:** Done  

## Preconditions

_None — a missing network connection is handled when the feed is retrieved (A5)._

## Main Success Scenario

1. Reader chooses to add a feed.
2. System displays the add-feed form with an explanation that a feed address or a website address may be entered.
3. Reader enters an address and confirms (BR-010).
4. System normalizes the address and checks that it is a valid web address.
5. System retrieves the document at the address from the Feed Publisher.
6. System recognizes the document as a feed and reads its title, website, and articles.
7. System checks that the Reader is not yet subscribed to the feed.
8. System adds the feed to the subscription list, sorted by title, and stores its articles as unread.
9. System saves the library and closes the form.

## Alternative Flows

### A1: Address Prefilled from Clipboard

**Trigger:** On the Mac, the clipboard holds a web or feed address without spaces when the form opens (step 2)  
**Flow:**

1. System prefills the address field with the clipboard content.
2. Use case continues at step 3.

### A2: Invalid Address

**Trigger:** The address is not a web address with a host name (step 4)  
**Flow:**

1. System displays the message "That doesn't look like a valid web address." in the form.
2. Reader corrects the address or cancels.
3. Use case continues at step 3. *(or ends when the Reader cancels)*

### A3: Website Instead of Feed

**Trigger:** The document retrieved in step 5 is a web page, not a feed (step 6)  
**Flow:**

1. System looks for a feed the web page advertises.
2. System retrieves the first advertised feed from the Feed Publisher.
3. Use case continues at step 6; an advertised feed that is again not a feed is handled as unreadable (A5).

### A4: No Feed Found

**Trigger:** The web page advertises no feed (step 6)  
**Flow:**

1. System displays the message "No feed was found at that address." in the form.
2. Reader corrects the address or cancels.
3. Use case continues at step 3. *(or ends when the Reader cancels)*

### A5: Feed Publisher Unreachable or Feed Unreadable

**Trigger:** The Feed Publisher does not answer within the response time limit (BR-007) or answers with an error, for the entered address or for the advertised feed, or the retrieved feed cannot be read (step 5 or step 6)  
**Flow:**

1. System displays a message that describes the problem in the form.
2. Reader corrects the address or cancels.
3. Use case continues at step 3. *(or ends when the Reader cancels)*

### A6: Already Subscribed

**Trigger:** The library already holds a feed with the same final feed address (step 7)  
**Flow:**

1. System displays the message "You are already subscribed to this feed." in the form.
2. Reader corrects the address or cancels.
3. Use case continues at step 3. *(or ends when the Reader cancels)*

### A7: Reader Cancels

**Trigger:** Reader cancels the form before confirming, or while the address is being checked and the feed retrieved (step 3 or step 5)  
**Flow:**

1. System abandons a retrieval that is still running (BR-009).
2. System closes the form without changes.
3. Use case ends.

### A8: Library Cannot Be Saved

**Trigger:** The library cannot be saved (step 9)  
**Flow:**

1. System removes the feed and its articles from the library again (BR-008).
2. System displays a message in the form that the feed could not be saved.
3. Reader confirms again or cancels.
4. Use case continues at step 4. *(or ends when the Reader cancels)*

## Postconditions

### Success Postconditions

- The feed is stored in the library with its title, final feed address, and website
- The feed's current articles are stored as unread and not starred
- The library is saved

### Failure Postconditions

- No feed is added to the library
- No article is stored

## Business Rules

### BR-001: Accepted Addresses

Leading and trailing spaces are ignored. An address starting with `feed:` is treated as the web address that follows it: `feed:https://example.com/rss` becomes `https://example.com/rss`, and `feed://example.com/rss` becomes `https://example.com/rss`. An address without a scheme is completed to a secure web address (`https://`). Only `http` and `https` addresses with a host name are accepted.

### BR-002: No Duplicate Subscriptions

A feed address can be subscribed only once. The final feed address — the address the feed was retrieved from after redirects and feed discovery — is the one stored, and the comparison uses it.

### BR-003: Feed Discovery

When a website address is entered, the first RSS or Atom feed the web page advertises as an alternate version is subscribed. Discovery takes one step only: when the advertised address does not deliver a feed, no further web page is searched.

### BR-004: Feed Title

The feed title is the feed's own title as plain text, at most 200 characters: a longer title is cut to 199 characters and ends in an ellipsis (…). When the feed has no title, the host name of the feed address is used.

### BR-005: Subscription Order

Subscriptions are listed alphabetically by title, ignoring case.

### BR-006: Article Rules on Subscribe

The first articles are recognized, identified, and named by the same rules as a refresh (UC-003 BR-003, UC-003 BR-004, UC-003 BR-005, UC-003 BR-006).

### BR-007: Response Time Limit

A Feed Publisher that does not answer within 30 seconds counts as unreachable, as in a refresh (UC-003 BR-010).

### BR-008: Only Saved Subscriptions Are Added

A feed whose subscription cannot be saved is not added: it and its articles are removed from the library again.

### BR-009: Cancelling Adds No Feed

The Reader can cancel until the library is saved. A cancelled subscription adds no feed and no article, even when the retrieval would still have succeeded.

### BR-010: An Address Is Required

The Reader can confirm the form only when the address field holds something other than spaces. With an empty address the form cannot be confirmed, and no message is shown.
