# Use Case: Export Subscriptions

## Overview

**Use Case ID:** UC-007  
**Use Case Name:** Export Subscriptions  
**Primary Actor:** Reader  
**Goal:** Save the subscription list to a file, to back it up or move it to another feed reader  
**Trigger:** The Reader chooses to export the subscriptions  
**Status:** Draft  

## Preconditions

- On iPhone and iPad, the library holds at least one feed

## Main Success Scenario

1. Reader chooses to export subscriptions.
2. System asks where to save the file and proposes the name "Subscriptions.opml".
3. Reader confirms the location and name.
4. System writes every subscription with its title, feed address, and website to the file.

## Alternative Flows

### A1: File Cannot Be Written

**Trigger:** The file cannot be saved at the chosen location (step 4)  
**Flow:**

1. System displays an error message that describes the problem.
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

## Business Rules

### BR-001: Export Format

Subscriptions are exported as an OPML 2.0 subscription list without folders. Each entry carries the feed title, the feed address, and the website when the feed names one. Articles and their read or starred states are not exported.
