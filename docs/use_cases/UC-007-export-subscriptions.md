# Use Case: Export Subscriptions

## Overview

**Use Case ID:** UC-007  
**Use Case Name:** Export Subscriptions  
**Primary Actor:** Reader  
**Goal:** Save the subscription list to a file, to back it up or move it to another feed reader  
**Trigger:** The Reader chooses to export the subscriptions  
**Status:** Done  

## Preconditions

- The library holds at least one feed

## Main Success Scenario

1. Reader chooses to export subscriptions.
2. System asks where to save the file and proposes the name "Subscriptions.opml".
3. Reader confirms the location and name.
4. System writes every subscription with its title, feed address, and website to the file (BR-001, BR-002).

## Alternative Flows

### A1: File Cannot Be Written

**Trigger:** The file cannot be saved at the chosen location (step 4)  
**Flow:**

1. System displays the message "The subscriptions could not be exported.", whatever kept the file from being written.
2. Use case ends.

### A2: Reader Cancels

**Trigger:** Reader cancels the save dialog (step 3)  
**Flow:**

1. Use case ends.

## Postconditions

### Success Postconditions

- The file holds every subscription of the library
- The library is unchanged

### Failure Postconditions

- The library is unchanged
- No partly written file is left at the chosen location, and a file that already had the chosen name is unchanged

## Business Rules

### BR-001: Export Format

Subscriptions are exported as an OPML 2.0 subscription list without folders. Each entry carries the feed title, as both its text and its title, the feed address, and the website when the feed names one. Articles and their read or starred states are not exported.

### BR-002: Export Order

Entries are written in the subscription order (UC-001 BR-005).
