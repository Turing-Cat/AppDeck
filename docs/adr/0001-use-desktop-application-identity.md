# Use desktop-reported application identity

AppDeck groups app windows by the application identity reported by the
Wayland desktop. Desktop entries may supply presentation metadata but do not
change identity, and process ancestry is not used for grouping; this keeps the
model live and explainable even though some applications may report imperfect
identities.
