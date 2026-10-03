# Keep the app list live and stable

AppDeck derives its list from live desktop events instead of snapshots or
polling. Updates preserve the selected app whenever it still exists, new apps
never steal selection, and a disappearing selection moves to the nearest row;
this keeps displayed state current without making a user's keyboard target
jump unexpectedly.
