[Back to Guide Contents](README.md)

# Contracts

Contracts are the mod's job-board system. They are global, player-created listings that let one player promise a gold reward for work done by another player.

## What A Contract Contains

Each contract has:

- A title.
- A briefing or description.
- A gold reward.
- A creator.
- An optional assignee.
- A status.

## Contract States

- `Open`: available for someone else to take.
- `Assigned`: currently claimed by one player.
- `Completed`: paid out and finished.

## Creating A Contract

Use the `Contracts` tab and fill in:

- `Title`
- `Reward`
- `Briefing`

Then click `Create contract`.

## Assignment Rules

- Any player except the creator can assign themselves to an open contract.
- The current assignee can unassign themselves if the contract has not been completed.
- The creator cannot assign their own contract to themselves.
- When someone assigns themselves, the contract creator receives a notification naming the assignee and contract title.

## Paying Out A Contract

Only the creator can pay a contract, and only when:

- The contract is assigned.
- There is a valid assignee.
- The creator has enough gold to cover the reward.

When payment succeeds:

- Gold is transferred from the creator's force wallet to the assignee's force wallet.
- The contract becomes `Completed`.
- The paid time is recorded internally for status display.

## What The Contracts Tab Shows

The UI is split into two main parts:

- A contract list on the left with current entries and status markers.
- A detail and creation area on the right.

The selected contract view shows:

- Title
- Creator
- Reward
- Assignee
- Status
- Age
- Paid time, if already completed
- Full briefing text

## Typical Uses

- Paying someone to bring bulk materials.
- Posting ad hoc construction work.
- Outsourcing defense, rail, or factory expansion jobs.
- Running multiplayer team objectives with explicit rewards.

[Back to Guide Contents](README.md)
