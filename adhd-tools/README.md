# ADHD tools

Small, single-purpose tools built for one brain. Each folder is one tool.
The rest of this repository is the Supabase Swift client library and is unrelated.

## Hold That Thought

A one-screen inbox for the moments that go wrong:

- A good thought shows up and gets lost. The catch box takes it in two seconds. No sorting, no categories.
- Someone starts talking while you are mid-task. The orange button bookmarks what you were doing, takes the thought, and shows you a "back to it" card when they leave.
- Too many thoughts at once, so nothing gets done. Sort the pile one card at a time. Only one thing ever sits in **Now**, with a "next small step" under it.
- Two conversations at once. The "Words for the moment" card holds short phrases to say out loud that buy you five seconds.

**Live page:** https://claude.ai/artifact/CW98GhnkpNfc14t7fn5K5o

On a phone, open the link in Safari or Chrome and use *Share → Add to Home Screen* so it opens like an app.

### How it stores things

- Published through Claude, the page keeps your items in that artifact's own database, so your phone and computer see the same list. Access is set so only the owner (and anyone the owner makes an Editor) can read the data.
- The database holds up to 5,000 items in total. The page shows the newest 1,000. Done items count toward this, so use the "Clear done from more than a week ago" button inside **Done today** now and then.
- Opened outside Claude (for example this file straight from disk), it falls back to saving in that browser only and says so in the top right.

### Files

- `hold-that-thought/index.html` is the whole tool: markup, styles, and script in one file, no build step.
  It is written in the shape Claude's artifact publisher expects (no `<html>` or `<head>` wrapper; the publisher adds those), so it will look plain if opened directly from disk.

### Changing it

Edit `index.html` here, then ask Claude in a session on this repo to republish it to the same link. Keep the `<title>` as is so the artifact keeps its name and URL.
