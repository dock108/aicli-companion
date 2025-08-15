# User Testing Notes

## Overview
This document tracks issues, observations, and improvements discovered during user testing of the AICLI Companion app.

## Test Cases and Results

### Test Case #1: Message Persistence on Project Navigation
**Test Steps**: Send "hello", wait for response, leave project, return to project chat
**Expected**: Messages persist correctly without duplication
**Result**: ❌ FAIL - Received message was duplicated in thread upon returning to project
**Date**: 2025-08-15

## Issues Discovered

### Priority: High
<!-- Critical issues that block core functionality -->

- **Message duplication on project re-entry** - When leaving and returning to a project, received messages are duplicated in the chat thread (Test Case #1)

### Priority: Medium
<!-- Issues that affect user experience but have workarounds -->

- **iPad: Two settings icons visible** - There are two settings icons showing on iPad. The higher one doesn't appear to be visible on iPhone anywhere.

### Priority: Low
<!-- Minor issues or nice-to-have improvements -->

## User Feedback

### Feature Requests

### UX/UI Observations

### Performance Issues

## Action Items
<!-- Tasks to address discovered issues -->

---

**Created**: 2025-08-12
**Last Updated**: 2025-08-15