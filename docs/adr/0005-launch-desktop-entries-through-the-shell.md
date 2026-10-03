# Launch desktop entries through the shell

AppDeck starts only visible desktop application entries and delegates each
Start Running request to Omarchy's shared application library, with the desktop
entry's native execute method as a host-compatibility fallback. This keeps
desktop-file parsing, terminal handling, application scoping, and hidden-entry
policy at the desktop boundary instead of turning the search box into a command
runner.
