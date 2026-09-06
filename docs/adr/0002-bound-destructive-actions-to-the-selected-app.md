# Bound destructive actions to the selected app

Graceful Close and Kill target every app window in the selected app, so
the action scope matches the object shown by each row. Graceful Close sends
requests without confirmation, while Kill always requires confirmation,
uses exact desktop-reported window owners, and never requests elevated
privileges.
