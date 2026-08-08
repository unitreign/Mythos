<div align="center">

<img src="images/logow.png" width="96" alt="Mythos Logo" />

# Mythos

**A web novel library for KOReader. Browse, track, and export your favourite stories as EPUBs — right on your e-reader.**

[![Release](https://img.shields.io/github/v/release/unitreign/mythos?label=version&color=black)](https://github.com/unitreign/mythos/releases/latest)
[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0-black)](LICENSE)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-support-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/unitreign)

</div>

---

Mythos is a [KOReader](https://github.com/koreader/koreader) plugin that brings web novel browsing directly to your e-ink device. Find novels, track the ones you're reading, pick your chapters, and export them as properly structured EPUB files with no computer needed.

## Screenshots

<div align="center">

| Browse popular titles | Novel details & tracking |
|:---:|:---:|
| <img src="images/screenshots/ss-browse.png" width="280" /> | <img src="images/screenshots/ss-novel-detail.png" width="280" /> |

| Chapter selection | Export options |
|:---:|:---:|
| <img src="images/screenshots/ss-chapters.png" width="280" /> | <img src="images/screenshots/ss-export-options.png" width="280" /> |

| Your library | Exported EPUBs in KOReader |
|:---:|:---:|
| <img src="images/screenshots/ss-library.png" width="280" /> | <img src="images/screenshots/ss-exported-books.png" width="280" /> |

| Search | Sources & extensions |
|:---:|:---:|
| <img src="images/screenshots/ss-search.png" width="280" /> | <img src="images/screenshots/ss-sources.png" width="280" /> |

</div>

## Features

- **Browse & search** — explore popular novels or search by title directly from your device
- **Track novels** — save novels to your library and check for new chapters at a glance
- **Chapter selection** — pick all chapters, deselect what you don't want, or cherry-pick a custom range
- **Flexible export** — export as a single EPUB, one EPUB per chapter, or bundled into volumes of N chapters
- **Organised output** — EPUBs are saved to `Mythos/Series/Book.epub` with cover art embedded
- **Extension system** — sources are installable plugins; add new sites without updating Mythos itself
- **Chapter caching** — re-opening a tracked novel is fast; only new chapters are fetched

## Requirements

- [KOReader](https://github.com/koreader/koreader), any reasonably recent build
- A Kobo, Kindle, or other device KOReader supports
- Wi-Fi for fetching novels; exports work fully offline after that

## Installation

1. Go to the [Releases](https://github.com/unitreign/mythos/releases/latest) page and download `mythos.koplugin.zip`
2. Extract the zip and you should get a folder called `mythos.koplugin`
3. Copy that folder into KOReader's plugins directory:
   - **Kobo:** `/mnt/onboard/.adds/koreader/plugins/`
   - **Kindle:** `extensions/koreader/plugins/`
   - Other devices: wherever your KOReader `plugins/` folder lives
4. Restart KOReader
5. Open the menu, go to **Tools**, and tap **Mythos**

## Getting Started

### 1. Add a source

Go to the **Sources** tab and tap **+ Add Repo**. Type a GitHub repo URL in short form:

```
github.com/unitreign/mythosext
```

Tap **Refresh Index** to load available extensions, then tap one under **Available** to install it.

> The official extension repository is **[unitreign/mythosext](https://github.com/unitreign/mythosext)**. Start here.

### 2. Browse or search

Switch to the **Browse** tab. Select your installed source from the list to see popular titles, or tap **Search** at the top to find something specific.

### 3. Track a novel

Tap any novel to open its detail page. Tap **Track Novel** to add it to your library. Tracked novels appear in the **Library** tab with their chapter count shown. Tap **Refresh** on the library screen to check for new chapters across everything you're following.

### 4. Export to EPUB

From a novel's detail page, switch to the **Chapters** tab. Tap **Select All** (or pick individual chapters), then tap **Export**. Choose your format and Mythos will build the EPUB files and save them to your device. Open them in KOReader like any other book.

## Tips

A few things that are not immediately obvious:

- **Jump to a page in the chapter list** — in the Chapters tab, tap the page indicator in the middle of the nav bar (e.g. `1 / 315`) to open a dialog where you can type a page number and jump straight there. Handy for long series.
- **Remove a repo** — in the Sources tab, hold on any repo row to get a remove prompt.
- **Uninstall an extension** — tap an installed extension to open its settings, where you'll find an Uninstall option. Or hold the row for a quick uninstall prompt.
- **Force-refresh a novel's chapter list** — on the novel detail page, tap **Refresh Chapter List** to bypass the cache and re-fetch from the source. Useful if a chapter count looks wrong. 
- **Library refresh** — the **Refresh** button at the top of the Library tab checks every tracked novel for new chapters in one go. This will take time based on your library. The more tracked books there are, the longer it takes. **Force-refresh a novel's chapter list** is recommended.

## Extensions

Mythos uses a source extension system. Each extension is a small Lua file that teaches Mythos how to talk to one website. Extensions are installed from repos, which are collections of extensions with an index file.

**Available extensions:** [github.com/unitreign/mythosext](https://github.com/unitreign/mythosext)

### Installing an extension

1. **Sources** tab, tap **+ Add Repo**, enter `github.com/unitreign/mythosext`
2. Tap **Refresh Index**
3. Tap the extension you want under **Available** and it installs immediately

### Writing your own extension

Want to add support for a new site? See the docs at [documentations](github.com/unitreign/mythosext/blob/main/docs/). It covers the full API, required methods, and a worked example. Finished extensions can be submitted as a pull request to mythosext.

## Disclaimer

Mythos is a reading companion tool, not a piracy tool. It only accesses freely available content that sites publicly serve to any visitor. It does not bypass paywalls, unlock premium or coin-gated chapters, scrape paid content, or circumvent any access controls. Locked chapters are clearly marked and cannot be exported. Please respect the terms of service of the sites you access and support authors whose work you enjoy.

## License

Mythos is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE).

The extension repository ([mythosext](https://github.com/unitreign/mythosext)) is licensed under the **MIT License**.

---

<div align="center">

If Mythos is useful to you, consider supporting development.

[![Support on Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/unitreign)

</div>
