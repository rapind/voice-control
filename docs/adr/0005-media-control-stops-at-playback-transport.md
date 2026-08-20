# ADR 0005: Media control stops at playback transport

## Status

Accepted

## Decision

Voice Control supports global YouTube Music transport through macOS media events. The direct commands are `media play`, `media pause`, `media next`, and `media previous`. They operate on the active system media session without changing application focus.

`media launch` opens the installed YouTube Music Chrome app, then restores focus to the application that was frontmost when the command ran.

Voice Control does not list, match, or start playlists by name. It does not store Google OAuth credentials or request YouTube API access.

The official YouTube Data API is not a YouTube Music playback API. Its authenticated playlist listing covers playlists owned by the account, not the complete YouTube Music library, saved albums, or device downloads. It can provide playlist and video identifiers, but it cannot tell the YouTube Music app to begin playback.

The Chrome-installed YouTube Music app is an app shim with a fixed home URL. Its bundle does not declare a URL handler, so asking macOS to open a playlist URL with that app launches or focuses the app while discarding the requested URL. Chrome's explicit `--app=<url>` mode can navigate to a playlist, but it creates another app-style window. Reusing an existing Chrome window requires browser automation permission and couples voice control to Chrome UI behavior.

## Consequences

- Playback transport works with any application that owns the current macOS media session, including YouTube Music.
- Launching YouTube Music briefly changes focus, then returns the user to the previous application.
- Playlist choice remains a manual action inside YouTube Music.
- The daemon has no Google client secret, refresh token, YouTube quota usage, or browser-automation permission to manage.
- Playlist voice selection should be reconsidered only if YouTube Music exposes a supported playback API or the chosen music client gains a reliable deep-link interface.

