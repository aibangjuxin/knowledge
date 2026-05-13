# Request for Comments (RFC)

## What is an RFC?

**RFC** stands for **Request for Comments**.

In its most general sense, an RFC is a document that describes a proposed change, new feature, or standard, and is distributed to a group of people to gather feedback, suggestions, and approval before implementation begins.

## Origins: The Internet Engineering Task Force (IETF)

The term originated with the **Internet Engineering Task Force (IETF)** in 1969.
- **Purpose**: To define protocols and standards for the Internet (and its predecessor, ARPANET).
- **Famous Examples**:
    - **RFC 791**: Internet Protocol (IP)
    - **RFC 793**: Transmission Control Protocol (TCP)
    - **RFC 2616**: Hypertext Transfer Protocol (HTTP/1.1)
- **Nature**: These documents start as drafts and, through peer review and consensus, can become official Internet Standards. Despite the name "Request for Comments," published IETF RFCs are often authoritative specifications.

## RFCs in Modern Software Engineering

In modern software companies (like Google, Uber, Airbnb, etc.), "RFC" has been adopted as a standard practice for **technical design documents**.

### Why use them?
1.  **Consensus Building**: Align the team on *what* is being built and *why* before writing code.
2.  **Feedback Loop**: Catch design flaws early through peer review.
3.  **Documentation**: Serve as a historical record of design decisions and trade-offs.
4.  **Knowledge Sharing**: disseminate context to the wider team.

### When to write one?
- When introducing a new architectural component.
- When making a significant change to an existing system.
- When the implementation is complex or has multiple potential solutions.
- *Not* usually required for small bug fixes or minor refactoring.

## Typical RFC Structure

A good RFC usually includes the following sections:

1.  **Title & Metadata**: Author, status (Draft, In Review, Approved), date.
2.  **Summary / Abstract**: A high-level overview of the proposal.
3.  **Motivation / Problem Statement**: Why are we doing this? What problem are we solving?
4.  **Proposed Solution**: Technical details of the design (architecture diagrams, API specs, data models).
5.  **Alternative Solutions**: What other approaches were considered and why were they rejected?
6.  **Trade-offs**: Pros and cons of the proposed solution (e.g., latency vs. consistency).
7.  **Unresolved Questions**: Open items that need discussion.
8.  **Security & Privacy Considerations**: How does this impact security?

## Summary

*   **Original Meaning**: Official documents defining Internet standards (IETF).
*   **Modern Usage**: Design documents used by engineering teams to plan and review changes.
*   **Goal**: To "request comments" and agree on a design before implementation.
