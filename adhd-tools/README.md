# ADHD tools

Small, single-purpose tools built for one brain. Each folder is one tool.
The rest of this repository is the Supabase Swift client library and is unrelated.

## Hold That Thought

**Live page:** https://claude.ai/artifact/CW98GhnkpNfc14t7fn5K5o

A phone-first page with three tabs and one giant button.

- **The big orange button.** Tap it and a full-screen box opens with the keyboard up. Tap the keyboard's mic and talk. It bookmarks whatever you were doing first, so you can get back to it. Closing the box saves what you said, and a half-finished thought is saved the next time the page opens.
- **Screenshots.** Tap *Add screenshot* and pick from Photos, paste one, or drag files onto the page on a computer. Each one is shrunk, stored, and read by Claude, which fills in a title, the kind of post (ad, video, post, product), the brand, the headline, the words in the picture, and search tags.
- **Saved tab.** Search by brand, words in the picture, or why you saved it. Search forgives typos. Filter by kind. Open one to add a note, turn it into a task, ask Claude to read it again, or delete it.
- **Pile tab.** Everything you caught, sorted one card at a time into Do it now, Next, Later, or Let it go. A long rambling voice note can be split into separate thoughts by Claude.
- **Now tab.** One thing at a time, with a "next small step" line and a "Back to it" card after an interruption.

### Phone setup

1. Open the live page in Safari, then use *Share → Add to Home Screen*.
2. Fastest screenshot path on iPhone: take the screenshot, open the preview, tap the checkmark or Done, choose *Copy and Delete*. Then long-press the dashed box on the page and tap *Paste*. The screenshot never lands in Photos.

### One-press talk

Claude's published pages can't use the microphone, so the orange button can't listen by itself. An iPhone Shortcut can. It starts listening the moment it runs, then opens the page with your words in the link, and the page saves them to Caught. The page has the same steps under *Set up one-press talk*, with a copy button for the link.

Build it once in the Shortcuts app:

1. Tap **+** and name the shortcut **Hold That Thought**.
2. Add **Dictate Text**. Set Stop Listening to **After Pause**.
3. Add **Base64 Encode**. Set Line Breaks to **None**.
4. Add **Replace Text** three times: `+` with `-`, `/` with `_`, and `=` with nothing.
5. Add **Random Number** from 1 to 999999999.
6. Add **Text** containing the link below, then the Random Number variable, a dot, and the Updated Text variable.
7. Add **Open URLs**.

```
https://claude.ai/artifact/CW98GhnkpNfc14t7fn5K5o#say.
```

Then give it a physical button: the Action Button (*Settings → Action Button → Shortcut*), Back Tap (*Settings → Accessibility → Touch → Back Tap*), or Siri ("Hey Siri, Hold That Thought"). Test it by saying "testing one two"; the page should open and show "Caught from your voice".

Once the test works, the setup sheet has a switch that makes the orange button start the Shortcut on that device. If the button then does nothing when tapped, the app showing the page is blocking Shortcut links; turn the switch off and use the Action Button. *Type instead* under the button always opens the keyboard talk box.

How the hand-off works: the link ends in `#say.<random number>.<words>`, where the words are base64url text, because a page link may only carry letters, digits, and `. _ ~ -`. The page decodes the words, saves them, bookmarks the Now task, and clears the link. It remembers each random number on that device for a year and on the saved item, so reopening an old tab never saves the same thought twice. Without the random number, repeats within 12 hours are ignored.

### Storage and limits

| What | Limit |
| --- | --- |
| Thoughts and screenshot records | 5,000 in the page's database; the page loads the newest 1,000 |
| Screenshot files | 1 GB and 5,000 files. Each screenshot stores two files (full size and thumbnail), about 250 to 450 KB together, so roughly 2,500 screenshots |
| Claude labels and splitting | Uses your own Claude plan. The first use in a session asks you to allow it |

Access rules let only the owner, and anyone the owner makes an Editor, read or write the data.
Opened outside Claude, the page falls back to saving thoughts in that browser only, and screenshots are turned off.

### Keyboard shortcuts

| Key | Action |
| --- | --- |
| `n` or `t` | Open the talk box |
| `/` | Search saved screenshots |
| `1` `2` `3` | Now, Pile, Saved |
| `Esc` | Close the top sheet (the talk box saves on close) |

Link endings `#talk`, `#pile` and `#saved` open the page on that screen. `#say.` is the voice hand-off described above.

### Open-source tools considered

| Tool | License | Fit |
| --- | --- | --- |
| Karakeep (was Hoarder) | AGPL-3.0 | Best stand-alone app for "save everything": iOS share sheet, AI tags, OCR. Self-host or paid cloud |
| Immich | AGPL-3.0 | Backs up the Screenshots album automatically and searches text in images. Needs your own server |
| Ente Photos | AGPL-3.0 | Hosted, 10 GB free, searches by description but not by exact words |
| Linkwarden | AGPL-3.0 | Links only from the phone share sheet, not screenshots |
| whisper.cpp, Vosk, Moonshine, transformers.js | MIT / Apache-2.0 | Can't run inside a Claude page: the mic and model downloads are blocked |
| Tesseract.js | Apache-2.0 | Can't run inside a Claude page: it downloads language data at runtime. Claude's own image reading replaces it |
| Fuse.js 7.2.0 | Apache-2.0 | Used here for typo-tolerant search, loaded from jsDelivr with an integrity hash. If it fails to load, search still does exact matching |

### Files

- `hold-that-thought/index.html` is the whole tool: markup, styles, and script in one file, no build step.
  It is written in the shape Claude's artifact publisher expects (no `<html>` or `<head>` wrapper; the publisher adds those), so it looks plain if opened straight from disk.
  It targets the artifact runtime contract 0.2.61 and declares the `db`, `assets` and `sample` capabilities.

### Changing it

Edit `index.html` here, then ask Claude in a session on this repo to republish it to the same link with the same capabilities. Keep the `<title>` so the artifact keeps its name.
